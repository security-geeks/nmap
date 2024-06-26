local coroutine = require "coroutine"
local dhcp6 = require "dhcp6"
local nmap = require "nmap"
local stdnse = require "stdnse"
local table = require "table"

description = [[
Sends a DHCPv6 request (Solicit) to the DHCPv6 multicast address,
parses the response, then extracts and prints the address along with
any options returned by the server.

The script requires Nmap to be run in privileged mode as it binds the socket
to a privileged port (udp/546).
]]

---
-- @see broadcast-dhcp-discover.nse
-- @see dhcp-discover.nse
--
-- @usage
-- nmap -6 --script broadcast-dhcp6-discover
--
-- @output
-- | broadcast-dhcp6-discover:
-- |   Interface: en0
-- |     Message type: Advertise
-- |     Transaction id: 74401
-- |     Options
-- |       Client identifier: MAC: 68:AB:CD:EF:AB:CD; Time: 2012-01-24 20:36:48
-- |       Server identifier: MAC: 08:FE:DC:BA:98:76; Time: 2012-01-20 11:44:58
-- |       Non-temporary Address: 2001:db8:1:2:0:0:0:1000
-- |       DNS Servers: 2001:db8:0:0:0:0:0:35
-- |       Domain Search: example.com, sub.example.com
-- |_      NTP Servers: 2001:db8:1111:0:0:0:0:123, 2001:db8:1111:0:0:0:0:124
--

author = "Patrik Karlsson"
license = "Same as Nmap--See https://nmap.org/book/man-legal.html"
categories = {"broadcast", "safe"}


prerule = function()
  if not nmap.is_privileged() then
    stdnse.verbose1("not running for lack of privileges.")
    return false
  end

  if nmap.address_family() ~= 'inet6' then
    stdnse.debug1("is IPv6 compatible only.")
    return false
  end
  return true
end

local function solicit(iface, result)
  local condvar = nmap.condvar(result)
  local helper = dhcp6.Helper:new(iface)
  if ( not(helper) ) then
    condvar "signal"
    return
  end

  local status, response = helper:solicit()
  if ( status ) then
    response.name=("Interface: %s"):format(iface)
    table.insert(result, response )
  end
  condvar "signal"
end

action = function(host, port)

  local ifs, result, threads = {}, {}, {}
  local condvar = nmap.condvar(result)

  local ifs = {}
  local collect_interfaces = function (if_table)
    if if_table and if_table.up == "up" and if_table.link=="ethernet" then
      ifs[if_table.device] = if_table
    end
  end
  stdnse.get_script_interfaces(collect_interfaces)

  for iface in pairs(ifs) do
    local co = stdnse.new_thread( solicit, iface, result )
    threads[co] = true
  end

  -- wait until the probes are all done
  repeat
    for thread in pairs(threads) do
      if coroutine.status(thread) == "dead" then
        threads[thread] = nil
      end
    end
    if ( next(threads) ) then
      condvar "wait"
    end
  until next(threads) == nil

  return stdnse.format_output(true, result)
end
