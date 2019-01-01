--[[
Join queue Lua module for ET server
Author: a domestic cat (c) 2019
License: MIT
Source: https://github.com/adawolfa/et-lua-joinqueue
--]]

local clients = {}
local sv_maxclients = 64
local team_maxplayers = 0
local shrubbot = "shrubbot.cfg"
local level_priority
local level_override
local admins = {}
local futures = {}
local announces = { axis = "", allies = "", all = "" }
local pop = true
local put = true

function et_InitGame(levelTime, randomSeed, restart)

	et.RegisterModname("joinqueue.lua " .. et.FindSelf());

	sv_maxclients = tonumber(et.trap_Cvar_Get("sv_maxclients"))
	team_maxplayers = tonumber(et.trap_Cvar_Get("team_maxplayers"))

	et.trap_Cvar_Set("team_maxplayers", 0)

	for i = 0, sv_maxclients - 1 do

		local serialized = et.trap_Cvar_Get("jq_client" .. i)

		if serialized ~= nil then

			local client = {}

			for key, value in string.gfind(serialized, "(%w+)=\"([^\"]*)\"") do
				if key == "name" or key == "guid" then
					client[key] = value
				else
					client[key] = tonumber(value)
				end
			end

			clients[i] = client

		else
			clients[i] = nil
		end

	end

	local jq_shrubbot = et.trap_Cvar_Get("jq_shrubbot")

	if jq_shrubbot ~= "" then
		shrubbot = jq_shrubbot
	end

	local fd, len = et.trap_FS_FOpenFile(shrubbot, et.FS_READ)

	if len > -1 then

		local content = et.trap_FS_Read(fd, len)

		for guid, level in string.gfind(content, "[Gg]uid%s*=%s*(%x+)%s*\n[Ll]evel%s*=%s*(%d+)") do
			admins[string.lower(guid)] = tonumber(level)
		end

	end

	et.trap_FS_FCloseFile(fd)

	local jq_level_priority = et.trap_Cvar_Get("jq_level_priority")
	local jq_level_override = et.trap_Cvar_Get("jq_level_override")

	if jq_level_priority ~= "" then
		level_priority = tonumber(jq_level_priority)
	end

	if jq_level_override ~= "" then
		level_override = tonumber(jq_level_override)
	end

	jq_Announce()

end

function et_ClientBegin(c)
	jq_UpdateClient(c)
	jq_PopQueue()
end

function et_ClientUserinfoChanged(c)
	jq_UpdateClient(c)
	jq_PopQueue()
end

function et_ClientCommand(c, command)

	if string.lower(command) == "team" then

		local team = string.lower(et.trap_Argv(1))

		if team == "a" then
			team = nil
		elseif team == "r" then
			team = 1
		elseif team == "b" then
			team = 2
		elseif team == "s" then
			jq_Remove(c)
			return 0
		else
			return 0
		end

		if clients[c].team == 1 or clients[c].team == 2 then
			if team == nil or (team ~= nil and team == clients[c].team) then
				return 1
			end
		end

		local class
		local weapon
		local weapon2

		if et.trap_Argc() > 2 then
			class = tonumber(et.trap_Argv(2))
		end

		if et.trap_Argc() > 3 then
			weapon = tonumber(et.trap_Argv(3))
		end

		if et.trap_Argc() > 4 then
			weapon2 = tonumber(et.trap_Argv(4))
		end

		if jq_Add(c, team, class, weapon, weapon2) then
			return 1
		end

	end

	return 0

end

function et_ConsoleCommand()

	if string.lower(et.trap_Argv(0)) == "ref" and et.trap_Argc() > 2 then

		local command = string.lower(et.trap_Argv(1))
		local team

		if command == "putaxis" then
			team = 1
		elseif command == "putallies" then
			team = 2
		elseif command == "remove" then
			team = 3
		else
			return 0
		end

		if not put then
			put = true
			return 0
		end

		local c = jq_FindClient(et.trap_Argv(2))

		if c ~= nil then

			if team == 3 then
				jq_Remove(c)
				return 0
			end

			et.G_Print("et_ConsoleCommand\n")
			if not jq_Add(c, team, nil, nil, nil) then
				return 0
			end

		end

		return 1

	end

	return 0

end

function et_ClientDisconnect(c)
	jq_Remove(c)
	clients[c] = nil
	jq_PopQueue()
end

function et_ShutdownGame(restart)

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil then

			local serialized = ""

			table.foreach(clients[i], function(key, value)
				serialized = serialized .. " " .. key .. "=\"" .. value .. "\""
			end)

			et.trap_Cvar_Set("jq_client" .. i, string.sub(serialized, 2, string.len(serialized)))

		else
			et.trap_Cvar_Set("jq_client" .. i, "")
		end

	end

	et.trap_Cvar_Set("team_maxplayers", team_maxplayers)

end

function et_RunFrame(levelTime)

	if table.getn(futures) > 0 then
		table.foreach(futures, function(i, future) future() end)
		futures = {}
	end

end

function jq_FindClient(term)

	local number = tonumber(term)

	if number ~= nil then
		return number
	end

	term = et.Q_CleanStr(term)

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil then

			local name = et.Q_CleanStr(clients[i].name)

			if name == term then
				return i
			end

		end

	end

	return nil

end

function jq_UpdateClient(c)

	if clients[c] == nil then
		clients[c] = {}
	end

	local userinfo = et.trap_GetUserinfo(c)

	clients[c].private = 0

	if et.trap_Cvar_Get("sv_privatepassword") ~= "" and et.Info_ValueForKey(userinfo, "password") == et.trap_Cvar_Get("sv_privatepassword") then
		clients[c].private = 1
	end

	clients[c].team = tonumber(et.gentity_get(c, "sess.sessionTeam"))
	clients[c].name = et.gentity_get(c, "pers.netname")
	clients[c].guid = string.lower(et.Info_ValueForKey(userinfo, "cl_guid"))

end

function jq_GetTeamFree()

	local axis = team_maxplayers
	local allies = team_maxplayers

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil then

			if clients[i].team == 1 and axis > 0 then
				axis = axis - 1
			elseif clients[i].team == 2 and allies > 0 then
				allies = allies - 1
			end

		end

	end

	return axis, allies

end

function jq_Add(c, team, class, weapon, weapon2)

	local axis, allies = jq_GetTeamFree()

	if (team == 1 and axis > 0) or (team == 2 and allies > 0) or (team == clients[c].team) then
		jq_Remove(c)
		return false
	end

	if team == nil and (axis > 0 or allies > 0) then

		if axis > allies then
			team = 1
		else
			team = 2
		end

		jq_PutTeam(c, team, class, weapon, weapon2)

		return true

	end

	if clients[c].private == 1 then
		jq_PutTeam(c, team, class, weapon, weapon2)
		return true
	end

	local position = 0

	if clients[c].queue ~= nil then
		position = clients[c].queue
	else

		if admins[clients[c].guid] ~= nil then

			if level_override ~= nil and admins[clients[c].guid] >= level_override then
				jq_PutTeam(c, team, class, weapon, weapon2)
				return true
			elseif level_priority ~= nil and admins[clients[c].guid] >= level_priority then
				position = jq_GetPosition(1) - 1
			end

		else
			position = jq_GetPosition(2) + 1
		end

	end

	clients[c].queue = position
	clients[c].queue_team = team
	clients[c].class = class
	clients[c].weapon = weapon
	clients[c].weapon2 = weapon2

	jq_Announce()
	return true

end

function jq_Remove(c)

	clients[c].queue = nil
	clients[c].queue_team = nil
	clients[c].class = nil
	clients[c].weapon = nil
	clients[c].weapon2 = nil

	jq_Announce()

end

function jq_PutTeam(c, team, class, weapon, weapon2)

	jq_Remove(c)

	put = false

	table.insert(futures, function()

		if team == 1 then
			et.trap_SendConsoleCommand(et.EXEC_APPEND, "ref putaxis " .. c .. "\n")
		else
			et.trap_SendConsoleCommand(et.EXEC_APPEND, "ref putallies " .. c .. "\n")
		end

		if class ~= nil then
			et.gentity_set(c, "sess.latchPlayerType", class)
		end

		if weapon ~= nil then
			et.gentity_set(c, "sess.latchPlayerWeapon", weapon)
		end

		if weapon2 ~= nil then
			et.gentity_set(c, "sess.latchPlayerWeapon2", weapon2)
		end

	end)

end

function jq_PopQueue()

	if not pop then
		return
	end

	local axis, allies = jq_GetTeamFree()

	if axis == 0 and allies == 0 then
		return
	end

	table.foreach(jq_GetQueue(nil), function(i, item)

		local team = item.queue_team

		if team == nil then
			if axis > allies then
				team = 1
			else
				team = 2
			end
		end

		if (team == 1 and axis == 0) or (team == 2 and allies == 0) then
			return
		end

		if team == 1 then
			axis = axis - 1
		else
			allies = allies - 1
		end

		pop = false
		jq_PutTeam(item.i, team, item.class, item.weapon, item.weapon2)

	end)

	table.insert(futures, function()
		pop = true
	end)

	jq_Announce()

end

function jq_GetPosition(mode)

	local position = 0

	for i = 0, sv_maxclients - 1 do

		-- TODO: Multiple prioritized clients?
		if clients[i] ~= nil and clients[i].queue ~= nil and ((mode == 1 and clients[i].queue < position) or (mode == 2 and clients[i].queue > position)) then
			position = clients[i].queue
		end

	end

	return position

end

function jq_GetQueue(team)

	local items = {}

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil and clients[i].queue ~= nil and (team == nil or clients[i].queue_team == nil or clients[i].queue_team == team) then
			local client = { i = i }
			table.foreach(clients[i], function(key, value) client[key] = value end)
			table.insert(items, client)
		end

	end

	table.sort(items, function(a, b)
		return a.queue < b.queue
	end)

	return items

end

function jq_Announce()

	table.insert(futures, function()

		local axis = ""
		local allies = ""
		local all = ""

		local axisn = {}
		local alliesn = {}
		local alln = {}

		table.foreach(jq_GetQueue(1), function(i, item)

			if item.queue_team == nil then
				all = all .. "^7, " .. item.name
				alln[item.i] = true
			end

			axis = axis .. "^7, " .. item.name
			axisn[item.i] = true

		end)

		table.foreach(jq_GetQueue(2), function(i, item)

			allies = allies .. "^7, " .. item.name
			alliesn[item.i] = true

		end)

		axis = "^1AXIS ^7queue: " .. string.sub(axis, 5, string.len(axis))
		allies = "^4ALLIES ^7queue: " .. string.sub(allies, 5, string.len(allies))
		all = "^7Join queue: " .. string.sub(all, 5, string.len(all))

		if axis ~= announces.axis then
			table.foreach(axisn, function(i)
				if alln[i] == nil then
					et.trap_SendServerCommand(i, "b 8 \"" .. axis .. "\"\n")
				end
			end)
		end

		if allies ~= announces.allies then
			table.foreach(alliesn, function(i)
				if alln[i] == nil then
					et.trap_SendServerCommand(i, "b 8 \"" .. allies .. "\"\n")
				end
			end)
		end

		if all ~= announces.all then
			table.foreach(alln, function(i)
				et.trap_SendServerCommand(i, "b 8 \"" .. all .. "\"\n")
			end)
		end

		announces.axis = axis
		announces.allies = allies
		announces.all = all

	end)

end