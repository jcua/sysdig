--[[
Copyright (C) 2014 Draios inc.
 
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License version 2 as
published by the Free Software Foundation.


This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
--]]

-- Chisel description
description = "Given a filter on the command line, this chisel saves the events that are in a time range around filter matches, and that are on the SAME process/thread. The time rang can be adjusted with the dump_range_ms argument. For example, 'sysdig -caround evt.type=open and evt.failed=true' will save two seconds of activity around every failed open.";
short_description = "Export to file the events around the where the given filter matches.";
category = "Misc";
		   
-- Argument list
args = 
{
	{
		name = "dump_file_name", 
		description = "the name of the file where the chisel will write the events related to each syslog entry.", 
		argtype = "string",
		optional = false
	},
	{
		name = "dump_range_ms", 
		description = "the time interval to capture *before* and *after* each event, in milliseconds. For example, 500 means that 1 second around each displayed event (.5s before and .5s after) will be saved to <dump_file_name>. The default value for dump_range_ms is 1000.", 
		argtype = "int",
		optional = true
	},
}
-- Imports and globals
require "common"
terminal = require "ansiterminal"
terminal.enable_color(true)
local dump_file_name = nil
local dump_range_ms = "1000"
local entrylist = {}
local capturing = false

-- Argument notification callback
function on_set_arg(name, val)
    if name == "dump_file_name" then
        dump_file_name = val
        return true
    elseif name == "dump_range_ms" then
        dump_range_ms = val
        return true
    end

    return false
end

-- Initialization callback
function on_init()	
	-- Request the fields that we need
	fpname = chisel.request_field("proc.name")
	ftid = chisel.request_field("thread.tid")
	fetime = chisel.request_field("evt.time")

	is_tty = sysdig.is_tty()
	
	if sysdig.get_filter() == "" then
		print("no filter specified")
		return false
	end
	
	return true
end

function on_capture_start()
	if sysdig.is_live() then
		print("live capture not supported")
		return false
	end
	
	capturing = true

	return true
end

-- Event parsing callback
function on_event()	
	-- Extract the event details
	local pname = evt.field(fpname)
	local tid = evt.field(ftid)
	local etime = evt.field(fetime)
	
	if pname == nil then
		pname = "<NA>"
	end
	
	print(etime .. " " .. pname .. "(" .. tid .. ")")
	
	local hi, low = evt.get_ts()
	local tid = evt.field(ftid)
	table.insert(entrylist, {hi, low, tid})

	return true
end

function on_capture_end()
	if is_tty then
		print(terminal.reset)
	end

	if capturing then
		local sn = sysdig.get_evtsource_name()

		local args = "-F -r" .. sn .. " -w" .. dump_file_name .. " "
		
		for i, v in ipairs(entrylist) do
			if i ~= 1 then
				args = args .. " or "
			end
			
			args = args .. "(evt.around[" .. ts_to_str(v[1], v[2]) .. "]=" .. dump_range_ms .. " and thread.tid=" .. v[3] .. ")"
		end		

		print("\nSaving events around " .. #entrylist .. " syslog entries to " .. dump_file_name)
		sysdig.run_sysdig(args)
	end
end
