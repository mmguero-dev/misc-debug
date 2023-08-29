#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'slop'
require 'lru_redux'
require 'json'
require 'faraday'
require 'fuzzystringmatch'

def collect_values(hashes)
  # https://stackoverflow.com/q/5490952
  hashes.reduce({}){ |h, pairs| pairs.each { |k,v| (h[k] ||= []) << v}; h }
end

def crush(thing)
  if thing.is_a?(Array)
    thing.each_with_object([]) do |v, a|
      v = crush(v)
      a << v unless [nil, [], {}, "", "Unspecified", "unspecified"].include?(v)
    end
  elsif thing.is_a?(Hash)
    thing.each_with_object({}) do |(k,v), h|
      v = crush(v)
      h[k] = v unless [nil, [], {}, "", "Unspecified", "unspecified"].include?(v)
    end
  else
    thing
  end
end

NETBOX_PAGE_SIZE=50
AUTOPOPULATE_FUZZY_THRESHOLD=0.75

opts = Slop.parse do |o|
  o.string '-u', '--url', 'NetBox URL'
  o.string '-t', '--token', 'NetBox token', required: true
  o.string '-i', '--ip', 'Search by this IP address'
  o.string '-o', '--oui', 'Manuf match lookup by this OUI'
  o.bool '-v', '--verbose', 'enable verbose mode'
end
tokenHeader = { "Authorization" => "Token " + opts[:token],
                'Content-Type' => 'application/json',
                'Accept' => 'application/json' }


opts[:url] = opts[:url].delete_suffix("/")
netbox_url_suffix = "/netbox/api"
netbox_url_base = opts[:url].delete_suffix(netbox_url_suffix)

nb = Faraday.new(opts[:url]) do |conn|
  conn.request :authorization, 'Token', opts[:token]
  conn.request :json
  conn.response :json, :parser_options => { :symbolize_names => true }
end

vrfs = Array.new
devices = Array.new

# retrieve the list VRFs containing IP address prefixes containing the search key
query = {:contains => opts[:ip], :offset => 0, :limit => NETBOX_PAGE_SIZE}
begin
  while true do
    if (prefixes_response = nb.get('api/ipam/prefixes/', query).body) and prefixes_response.is_a?(Hash) then
      tmp_prefixes = prefixes_response.fetch(:results, [])
      tmp_prefixes.each do |p|
        if (vrf = p.fetch(:vrf, nil))
          # non-verbose output is flatter with just names { :name => "name", :id => "id", ... }
          # if verbose, include entire object as :details
          vrfs << { :name => vrf.fetch(:name, vrf.fetch(:display, nil)),
                    :id => vrf.fetch(:id, nil),
                    :site => ((site = p.fetch(:site, nil)) && site&.key?(:name)) ? site[:name] : site&.fetch(:display, nil),
                    :tenant => ((tenant = p.fetch(:tenant, nil)) && tenant&.key?(:name)) ? tenant[:name] : tenant&.fetch(:display, nil),
                    :url => p.fetch(:url, vrf.fetch(:url, nil)),
                    :details => opts[:verbose] ? vrf.merge({:prefix => p.tap { |h| h.delete(:vrf) }}) : nil }
        end
      end
      query[:offset] += tmp_prefixes.length()
      break unless (tmp_prefixes.length() >= NETBOX_PAGE_SIZE)
    else
      break
    end
  end
rescue Faraday::Error
  # give up aka do nothing
end
vrfs = collect_values(crush(vrfs))

query = {:address => opts[:ip], :offset => 0, :limit => NETBOX_PAGE_SIZE}
begin
  while true do
    if (ip_addresses_response = nb.get('api/ipam/ip-addresses/', query).body) and ip_addresses_response.is_a?(Hash) then
      tmp_ip_addresses = ip_addresses_response.fetch(:results, [])
      tmp_ip_addresses.each do |i|
        is_device = nil
        if (obj = i.fetch(:assigned_object, nil)) && ((device_obj = obj.fetch(:device, nil)) || (virtualized_obj = obj.fetch(:virtual_machine, nil)))
          is_device = !device_obj.nil?
          device = is_device ? device_obj : virtualized_obj
          # if we can, follow the :assigned_object's "full" device URL to get more information
          device = (device.key?(:url) and (full_device = nb.get(device[:url].delete_prefix(netbox_url_base).delete_prefix(netbox_url_suffix).delete_prefix("/")).body)) ? full_device : device
          device_id = device.fetch(:id, nil)
          device_site = ((site = device.fetch(:site, nil)) && site&.key?(:name)) ? site[:name] : site&.fetch(:display, nil)

          # look up service if requested (based on device/vm found and service port)
          services = Array.new
          service_query = { (is_device ? :device_id : :virtual_machine_id) => device_id, :offset => 0, :limit => NETBOX_PAGE_SIZE }
          while true do
            if (services_response = nb.get('api/ipam/services/', service_query).body) and services_response.is_a?(Hash) then
              tmp_services = services_response.fetch(:results, [])
              services.unshift(*tmp_services) unless tmp_services.nil? || tmp_services&.empty?
              service_query[:offset] += tmp_services.length()
              break unless (tmp_services.length() >= NETBOX_PAGE_SIZE)
            else
              break
            end
          end
          device[:service] = services

          # non-verbose output is flatter with just names { :name => "name", :id => "id", ... }
          # if verbose, include entire object as :details
          devices << { :name => device.fetch(:name, device.fetch(:display, nil)),
                       :id => device_id,
                       :url => device.fetch(:url, nil),
                       :service => device.fetch(:service, []).map {|s| s.fetch(:name, s.fetch(:display, nil)) },
                       :site => device_site,
                       :role => ((role = device.fetch(:role, device.fetch(:device_role, nil))) && role&.key?(:name)) ? role[:name] : role&.fetch(:display, nil),
                       :cluster => ((cluster = device.fetch(:cluster, nil)) && cluster&.key?(:name)) ? cluster[:name] : cluster&.fetch(:display, nil),
                       :device_type => ((dtype = device.fetch(:device_type, nil)) && dtype&.key?(:name)) ? dtype[:name] : dtype&.fetch(:display, nil),
                       :manufacturer => ((manuf = device.dig(:device_type, :manufacturer)) && manuf&.key?(:name)) ? manuf[:name] : manuf&.fetch(:display, nil),
                       :details => opts[:verbose] ? device : nil }
        end
      end
      query[:offset] += tmp_ip_addresses.length()
      break unless (tmp_ip_addresses.length() >= NETBOX_PAGE_SIZE)
    else
      break
    end
  end
rescue Faraday::Error
  # give up aka do nothing
end
devices = collect_values(crush(devices))
devices.fetch(:service, [])&.flatten!&.uniq!

manuf = nil
if !opts[:oui].nil? && !opts[:oui]&.empty? then
  _fuzzy_matcher = FuzzyStringMatch::JaroWinkler.create( :native )
  _manufs = Array.new
  # fetch the manufacturers to do the comparison. this is a lot of work
  # and not terribly fast but once the hash it populated it shouldn't happen too often
  _query = {:offset => 0, :limit => NETBOX_PAGE_SIZE}
  begin
    while true do
      if (_manufs_response = nb.get('api/dcim/manufacturers/', _query).body) and _manufs_response.is_a?(Hash) then
        _tmp_manufs = _manufs_response.fetch(:results, [])
        _tmp_manufs.each do |_manuf|
          _tmp_name = _manuf.fetch(:name, _manuf.fetch(:display, nil))
          _manufs << { :name => _tmp_name,
                       :id => _manuf.fetch(:id, nil),
                       :url => _manuf.fetch(:url, nil),
                       :match => _fuzzy_matcher.getDistance(_tmp_name.to_s.downcase, opts[:oui].to_s.downcase)
                     }
        end
        _query[:offset] += _tmp_manufs.length()
        break unless (_tmp_manufs.length() >= NETBOX_PAGE_SIZE)
      else
        break
      end
    end
  rescue Faraday::Error
    # give up aka do nothing
  end
  # return the manuf with the highest match
  manuf = _manufs.max_by{|k| k[:match] }
  if !manuf.is_a?(Hash) || (manuf.fetch(:match, 0.0) < AUTOPOPULATE_FUZZY_THRESHOLD) then
    # match was not close enough, set default ("unspecified") manufacturer
    manuf = { :name => "Unidentified",
              :match => manuf.fetch(:match, 0.0) }
  end
end

puts JSON.pretty_generate({:vrfs => vrfs,
                           :devices => devices,
                           :manuf => manuf})