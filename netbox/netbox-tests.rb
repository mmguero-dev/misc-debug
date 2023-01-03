#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'slop'
require 'lru_redux'
require 'json'
require 'faraday'

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

opts = Slop.parse do |o|
  o.string '-u', '--url', 'NetBox URL'
  o.string '-t', '--token', 'NetBox token', required: true
  o.string '-i', '--ip', 'Search by this IP address'
  o.bool '-v', '--verbose', 'enable verbose mode'
end
tokenHeader = { "Authorization" => "Token " + opts[:token],
                'Content-Type' => 'application/json',
                'Accept' => 'application/json' }

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
    if (prefixes_response = nb.get('/api/ipam/prefixes/', query).body) and prefixes_response.is_a?(Hash) then
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
    if (ip_addresses_response = nb.get('/api/ipam/ip-addresses/', query).body) and ip_addresses_response.is_a?(Hash) then
      tmp_ip_addresses = ip_addresses_response.fetch(:results, [])
      tmp_ip_addresses.each do |i|
        is_device = nil
        if (obj = i.fetch(:assigned_object, nil)) && ((device_obj = obj.fetch(:device, nil)) || (virtualized_obj = obj.fetch(:virtual_machine, nil)))
          is_device = !device_obj.nil?
          device = is_device ? device_obj : virtualized_obj
          # if we can, follow the :assigned_object's "full" device URL to get more information
          device = (device.key?(:url) and (full_device = nb.get(device[:url]).body)) ? full_device : device
          device_id = device.fetch(:id, nil)
          device_site = ((site = device.fetch(:site, nil)) && site&.key?(:name)) ? site[:name] : site&.fetch(:display, nil)

          # look up service if requested (based on device/vm found and service port)
          services = Array.new
          service_query = { (is_device ? :device_id : :virtual_machine_id) => device_id, :offset => 0, :limit => NETBOX_PAGE_SIZE }
          while true do
            if (services_response = nb.get('/api/ipam/services/', service_query).body) and services_response.is_a?(Hash) then
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

puts JSON.pretty_generate({:devices => devices})

