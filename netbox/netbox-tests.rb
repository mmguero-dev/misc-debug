#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'slop'
require 'lru_redux'
require 'json'
require 'faraday'

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
while true do
    tmpPrefixes = nb.get('/api/ipam/prefixes/', query).body.fetch(:results, [])
    tmpPrefixes.each do |p|
        if (vrf = p.fetch(:vrf, nil))
          vrfs << vrf
        end
    end
    query[:offset] += tmpPrefixes.length()
    break unless (tmpPrefixes.length() >= NETBOX_PAGE_SIZE)
end

# retrieve the list IP addresses where address matches the search key, limited to "assigned" addresses.
# then, for those IP addresses, search for devices pertaining to the interfaces assigned to each
# IP address (e.g., ipam.ip_address -> dcim.interface -> dcim.device, or
# ipam.ip_address -> virtualization.interface -> virtualization.virtual_machine)
query = {:address => opts[:ip], :offset => 0, :limit => NETBOX_PAGE_SIZE}
while true do
    tmpIpAddresses = nb.get('/api/ipam/ip-addresses/', query).body.fetch(:results, [])
    tmpIpAddresses.each do |i|
        if (obj = i.fetch(:assigned_object, nil)) && ((device = obj.fetch(:device, nil)) || (device = obj.fetch(:virtual_machine, nil)))
            devices << device
        end
    end
    query[:offset] += tmpIpAddresses.length()
    break unless (tmpIpAddresses.length() >= NETBOX_PAGE_SIZE)
end

puts JSON.pretty_generate({:vrfs => vrfs.uniq, :devices => devices.uniq})
