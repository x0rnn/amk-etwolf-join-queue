--[[
Join queue Lua module for ET server
Author: a domestic cat (c) 2019
License: MIT
Source: https://github.com/adawolfa/et-lua-joinqueue
--]]

local clients = {}
local sv_maxclients = 64
local team_maxplayers = 0
local team_maxcovertops
local team_maxfieldops
local team_maxmortars
local team_maxpanzers
local team_maxflamers
local team_maxmg42s
local team_maxriflegrenades
local g_teamforcebalance
local shrubbot = "shrubbot.cfg"
local level_priority
local level_override
local admins = {}
local futures = {}
local delayes = {}
local announces = { axis = "", allies = "", all = "", log = "" }
local pop = true
local put = true
local sound
local introduction
local banner
local banner_delay = 10000
local banner_interval = 90000
local tick = 0
local shuffles = false
local shoutcast_announcement = false

local WEAPON_MORTAR = 35
local WEAPON_PANZERFAUST = 5
local WEAPON_FLAMETHROWER = 6
local WEAPON_MG42 = 31
local WEAPON_K43 = 23
local WEAPON_GARAND = 24

local CLASS_SOLDIER = 0
local CLASS_MEDIC = 1
local CLASS_ENGINEER = 2
local CLASS_FIELDOPS = 3
local CLASS_COVERTOPS = 4

function et_InitGame(levelTime, randomSeed, restart)

	et.RegisterModname("joinqueue.lua " .. et.FindSelf());

	sv_maxclients = tonumber(et.trap_Cvar_Get("sv_maxclients"))
	team_maxplayers = tonumber(et.trap_Cvar_Get("team_maxplayers"))

	et.trap_Cvar_Set("team_maxplayers", 0)

	for i = 0, sv_maxclients - 1 do

		local serialized = et.trap_Cvar_Get("jq_client" .. i)

		if serialized ~= "" then

			local client = {}
			local valid = false

			for key, value in string.gfind(serialized, "([^= ]+)=\"([^\"]*)\"") do
				if key == "name" or key == "guid" then
					client[key] = value
					valid = true
				else
					client[key] = tonumber(value)
				end
			end

			if valid then
				clients[i] = client
			else
				clients[i] = nil
			end

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
	local jq_sound = et.trap_Cvar_Get("jq_sound")
	local jq_introduction = et.trap_Cvar_Get("jq_introduction")
	local jq_banner = et.trap_Cvar_Get("jq_banner")
	local jq_banner_delay = et.trap_Cvar_Get("jq_banner_delay")
	local jq_banner_interval = et.trap_Cvar_Get("jq_banner_interval")

	if jq_level_priority ~= "" then
		level_priority = tonumber(jq_level_priority)
	end

	if jq_level_override ~= "" then
		level_override = tonumber(jq_level_override)
	end

	if jq_sound ~= "" then
		sound = et.G_SoundIndex(jq_sound)
	end

	if jq_introduction ~= "" then
		introduction = jq_introduction
	end

	if jq_banner ~= "" then
		banner = jq_banner
	end

	if jq_banner_delay ~= "" then
		banner_delay = tonumber(jq_banner_delay) * 1000
	end

	if jq_banner_interval ~= "" then
		banner_interval = tonumber(jq_banner_interval) * 1000
	end

	team_maxfieldops = tonumber(et.trap_Cvar_Get("team_maxfieldops"))
	team_maxcovertops = tonumber(et.trap_Cvar_Get("team_maxcovertops"))
	team_maxmortars = tonumber(et.trap_Cvar_Get("team_maxmortars"))
	team_maxpanzers = tonumber(et.trap_Cvar_Get("team_maxpanzers"))
	team_maxflamers = tonumber(et.trap_Cvar_Get("team_maxflamers"))
	team_maxmg42s = tonumber(et.trap_Cvar_Get("team_maxmg42s"))
	team_maxriflegrenades = tonumber(et.trap_Cvar_Get("team_maxriflegrenades"))
	g_teamforcebalance = tonumber(et.trap_Cvar_Get("g_teamforcebalance"))

	jq_Announce(nil)

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

	command = string.lower(command)

	if command == "team" and clients[c] ~= nil then

		local team = string.lower(et.trap_Argv(1))

		if team == "a" then
			team = -1
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

			if team == -1 then
				return 1
			end

			if team == clients[c].team then
				jq_Remove(c)
				return 0
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

	elseif command == "ref" and et.trap_Argc() > 1 then

		local ref = string.lower(et.trap_Argv(1))

		if ref == "shuffleteamsxp_norestart" then
			shuffles = true
			table.insert(delayes, { func = function() shuffles = false end, frames = 40 })
		elseif ref == "shuffleteamsxp" then
			shuffles = true
		end

	elseif command == "queue" then
		jq_TellQueue(c)
		return 1
	elseif (command == "say" or command == "say_team" or command == "say_buddy" or command == "say_teamnl") and et.trap_Argc() > 1 and string.lower(et.trap_Argv(1)) == "!queue" then
		jq_TellQueue(c)
		return 1
	end

	return 0

end

function et_ConsoleCommand()

	if string.lower(et.trap_Argv(0)) == "ref" and et.trap_Argc() > 2 then

		local command = string.lower(et.trap_Argv(1))
		local force = false
		local team

		if command == "putaxis" then
			team = 1
		elseif command == "putallies" then
			team = 2
		elseif command == "putany" then
			team = -1
		elseif command == "remove" then
			team = 3
		elseif command == "shuffleteamsxp_norestart" then
			shuffles = true
			table.insert(delayes, { func = function() shuffles = false end, frames = 40 })
			return 0
		elseif command == "shuffleteamsxp" then
			shuffles = true
			return 0
		elseif command == "putaxisf" then
			team = 1
			force = true
		elseif command == "putalliesf" then
			team = 2
			force = true
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

			if force then
				jq_Remove(c)
				jq_PutTeam(c, team)
				return 1
			end

			if clients[c].team == 1 or clients[c].team == 2 then
				if team == -1 or (team ~= -1 and team == clients[c].team) then
					return 1
				end
			end

			if not jq_Add(c, team, nil, nil, nil) then
				if team == -1 then
					return 1
				else
					return 0
				end
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

function et_Quit()

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil then

			local serialized = ""

			table.foreach(clients[i], function(key, value)
				if key ~= "banner" then
					serialized = serialized .. " " .. key .. "=\"" .. value .. "\""
				end
			end)

			et.trap_Cvar_Set("jq_client" .. i, string.sub(serialized, 2, string.len(serialized)))

		else
			et.trap_Cvar_Set("jq_client" .. i, "")
		end

	end

	et.trap_Cvar_Set("team_maxplayers", team_maxplayers)

end

function et_Print(message)
	if shoutcast_announcement and string.sub(message, 1, 16) == "etpro shoutcast:" then
		et.trap_SendServerCommand(-1, "cp \"\"\n")
	end
end

function et_RunFrame(levelTime)

	if table.getn(futures) > 0 then
		table.foreach(futures, function(i, future) future() end)
		futures = {}
	end

	if table.getn(delayes) > 0 then

		local remains = {}

		table.foreach(delayes, function(i, delay)

			delay.frames = delay.frames - 1

			if delay.frames == 0 then
				delay.func()
			else
				table.insert(remains, delay)
			end

		end)

		delayes = remains

	end

	if tick + 1000 <= levelTime then

		tick = levelTime

		for i = 0, sv_maxclients - 1 do

			if clients[i] ~= nil and clients[i].team == 3 then

				if clients[i].banner == nil then
					clients[i].banner = tick + banner_delay
				elseif clients[i].banner < tick then
					jq_Banner(i)
					clients[i].banner = tick + banner_interval
				end

			end

		end

	end

end

function jq_FindClient(term)

	local number = tonumber(term)

	if number ~= nil then

		if clients[number] == nil then
			return nil
		end

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

	clients[c].override = 0
	clients[c].priority = 0
	clients[c].team = tonumber(et.gentity_get(c, "sess.sessionTeam"))
	clients[c].name = et.gentity_get(c, "pers.netname")
	clients[c].guid = string.lower(et.Info_ValueForKey(userinfo, "cl_guid"))

	if admins[clients[c].guid] ~= nil then

		if level_override ~= nil and admins[clients[c].guid] >= level_override then
			clients[c].override = 1
		end

		if level_priority ~= nil and admins[clients[c].guid] >= level_priority then
			clients[c].priority = 1
		end

	end

	local sv_privatepassword = et.trap_Cvar_Get("sv_privatepassword")
	local password = et.Info_ValueForKey(userinfo, "password")

	if clients[c].override == 0 and sv_privatepassword ~= "" and password == sv_privatepassword then
		clients[c].override = 1
	end

end

function jq_GetTeamFree()

	local axis = team_maxplayers
	local allies = team_maxplayers
	local axisReal = 0
	local alliesReal = 0

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil then

			if clients[i].override == 0 then
				if clients[i].team == 1 and axis > 0 then
					axis = axis - 1
				elseif clients[i].team == 2 and allies > 0 then
					allies = allies - 1
				end
			end

			if clients[i].team == 1 then
				axisReal = axisReal + 1
			elseif clients[i].team == 2 then
				alliesReal = alliesReal + 1
			end

		end

	end

	return axis, allies, axisReal, alliesReal

end

function jq_GetWeakerTeam()

	local axis = 0
	local allies = 0

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil then

			if clients[i].team == 1 then
				axis = axis + 1
			elseif clients[i].team == 2 then
				allies = allies + 1
			end

		end

	end

	if axis > allies then
		return 2
	else
		return 1
	end

end

function jq_Add(c, team, class, weapon, weapon2)

	local axis, allies, axisReal, alliesReal = jq_GetTeamFree()

	if (team == 1 and axis > 0) or (team == 2 and allies > 0) or (team == clients[c].team) then
		if jq_BalancingCanJoin(team, c, axisReal, alliesReal) and jq_RestrictionCanJoin(team, c, class, weapon) then
			jq_Remove(c)
			return false
		end
	end

	if (team == -1 and (axis > 0 or allies > 0)) or clients[c].override == 1 then

		if team == -1 then
			if (axis > 0 and allies > 0) or clients[c].override == 1 then
				team = jq_GetWeakerTeam()
			else
				if axis > 0 and jq_BalancingCanJoin(1, c, axisReal, alliesReal) then
					team = 1
				elseif allies > 0 and jq_BalancingCanJoin(2, c, axisReal, alliesReal) then
					team = 2
				end
			end
		end

		if team ~= -1 then
			jq_PutTeam(c, team, class, weapon, weapon2)
			return true
		end

	end

	local position = 0
	local new = true

	if clients[c].queue ~= nil then
		position = clients[c].queue
		new = false
	else
		position = jq_GetPosition(clients[c].priority) + 1
		jq_Introduce(c)
	end

	clients[c].queue = position
	clients[c].queue_team = team
	clients[c].class = class
	clients[c].weapon = weapon
	clients[c].weapon2 = weapon2

	if new then
		jq_Announce(nil)
	else
		jq_Announce(c)
	end

	return true

end

function jq_Remove(c)

	if clients[c] == nil then
		return
	end

	local removed = false

	if clients[c].queue ~= nil then
		removed = true
		jq_Shoutcaster(c, false)
	end

	clients[c].queue = nil
	clients[c].queue_team = nil
	clients[c].class = nil
	clients[c].weapon = nil
	clients[c].weapon2 = nil
	clients[c].banner = nil

	if removed then
		table.insert(futures, function()
			et.trap_SendServerCommand(c, "b 8 \"^7You have left the queue.\"\n")
		end)
	end

	jq_Announce(nil)

end

function jq_PutTeam(c, team, class, weapon, weapon2)

	jq_Remove(c)

	put = false

	table.insert(futures, function()

		if team == -1 then
			team = jq_GetWeakerTeam()
		end

		if team == 1 then
			et.trap_SendConsoleCommand(et.EXEC_APPEND, "ref putaxis " .. c .. "\n")
		else
			et.trap_SendConsoleCommand(et.EXEC_APPEND, "ref putallies " .. c .. "\n")
		end

		if class == nil then
			class = CLASS_MEDIC
		end

		if not jq_IsClassAllowed(team, class) then
			class = CLASS_MEDIC
			weapon = nil
			weapon2 = nil
		elseif not jq_IsWeaponAllowed(team, class, weapon) then
			weapon = nil
			weapon2 = nil
		end

		et.gentity_set(c, "sess.latchPlayerType", class)

		if weapon ~= nil then
			et.gentity_set(c, "sess.latchPlayerWeapon", weapon)
		end

		if weapon2 ~= nil then
			et.gentity_set(c, "sess.latchPlayerWeapon2", weapon2)
		end

	end)

end

function jq_PopQueue()

	if not pop or shuffles then
		return
	end

	local axis, allies, axisReal, alliesReal = jq_GetTeamFree()

	if axis == 0 and allies == 0 then
		return
	end

	table.foreach(jq_GetQueue(-1), function(i, item)

		local team = item.queue_team

		if team == -1 and item.override == 0 then
			if  g_teamforcebalance > 0 then
				if axis > 0 and jq_BalancingCanJoin(1, item.i, axisReal, alliesReal) then
					team = 1
				elseif allies > 0 and jq_BalancingCanJoin(2, item.i, axisReal, alliesReal) then
					team = 2
				end
			else
				if axis > allies then
					team = 1
				else
					team = 2
				end
			end
		end

		if (team == 1 and axis == 0) or (team == 2 and allies == 0) then
			return
		end

		if item.override == 0 then

			if team == -1 or not jq_BalancingCanJoin(team, item.i, axisReal, alliesReal) then
				return
			end

			if team == 1 then
				axis = axis - 1
			else
				allies = allies - 1
			end

		end

		if team == -1 then
			team = jq_GetWeakerTeam()
		end

		if team == 1 then
			axisReal = axisReal + 1
		else
			alliesReal = alliesReal + 1
		end

		pop = false

		jq_PutTeam(item.i, team, item.class, item.weapon, item.weapon2)
		et.G_LogPrint("etpro announce: Enqueued player [" .. et.Q_CleanStr(item.name) .. "] popped to team [" .. team .. "]\n");

		if sound ~= nil then
			table.insert(futures, function() et.G_ClientSound(item.i, sound) end)
		end

	end)

	table.insert(futures, function()
		pop = true
	end)

	jq_Announce(nil)

end

function jq_BalancingCanJoin(team, c, axisReal, alliesReal)

	if g_teamforcebalance < 1 then
		return true
	end

	if (clients[c].team == 3 and ((team == 1 and axisReal > alliesReal) or (team == 2 and alliesReal > axisReal))) then
		return false
	end

	if (clients[c].team == 1 and team == 2) or (clients[c].team == 2 and team == 1) then
		if team == 1 and axisReal >= alliesReal then
			return false
		elseif team == 2 and alliesReal >= axisReal then
			return false
		end
	end

	return true

end

function jq_RestrictionCanJoin(team, c, class, weapon)

	if class ~= nil and not jq_IsClassAllowed(team, class) then
		return false
	elseif weapon ~= nil and not jq_IsWeaponAllowed(team, class, weapon) then
		return false
	end

	return true

end

function jq_GetPosition(priority)

	local position = 0

	if priority == 0 then
		position = position + 500
	end

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil and clients[i].queue ~= nil and clients[i].priority == priority and clients[i].queue > position then
			position = clients[i].queue
		end

	end

	return position

end

function jq_GetQueue(team)

	local items = {}

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil and clients[i].queue ~= nil and (team == -1 or clients[i].queue_team == -1 or clients[i].queue_team == team) then
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

function jq_Announce(who)

	table.insert(futures, function()

		local axis = ""
		local allies = ""
		local all = ""

		local axisn = {}
		local alliesn = {}
		local alln = {}

		local log = ""

		table.foreach(jq_GetQueue(1), function(i, item)

			if item.queue_team == -1 then
				log = log .. "; (A) " .. et.Q_CleanStr(item.name)
			elseif item.queue_team == 1 then
				log = log .. "; (R) " .. et.Q_CleanStr(item.name)
			elseif item.queue_team == 2 then
				log = log .. "; (B) " .. et.Q_CleanStr(item.name)
			end

			if item.queue_team == -1 then
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

		if axis ~= announces.axis or who ~= nil then
			table.foreach(axisn, function(i)
				if alln[i] == nil and (who == nil or who == i) then
					et.trap_SendServerCommand(i, "b 8 \"" .. axis .. "\"\n")
				end
			end)
		end

		if allies ~= announces.allies or who ~= nil then
			table.foreach(alliesn, function(i)
				if alln[i] == nil and (who == nil or who == i) then
					et.trap_SendServerCommand(i, "b 8 \"" .. allies .. "\"\n")
				end
			end)
		end

		if all ~= announces.all or who ~= nil then
			table.foreach(alln, function(i)
				if who == nil or who == i then
					et.trap_SendServerCommand(i, "b 8 \"" .. all .. "\"\n")
				end
			end)
		end

		if log ~= "" then
			log = "etpro announce: Queue: " .. string.sub(log, 3, string.len(log)) .. "\n"
		else
			log = "etpro announce: Queue: empty\n"
		end

		if log ~= announces.log then
			et.G_LogPrint(log)
		end

		announces.axis = axis
		announces.allies = allies
		announces.all = all
		announces.log = log

	end)

end

function jq_CountClasses(team, class)

	local count = 0

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil and clients[i].team == team then
			if tonumber(et.gentity_get(i, "sess.latchPlayerType")) == class then
				count = count + 1
			end
		end

	end

	return count

end

function jq_IsClassAllowed(team, class)

	if team_maxfieldops > 0 and class == CLASS_FIELDOPS and jq_CountClasses(team, CLASS_FIELDOPS) >= team_maxfieldops then
		return false
	elseif team_maxcovertops > 0 and class == CLASS_COVERTOPS and jq_CountClasses(team, CLASS_COVERTOPS) >= team_maxcovertops then
		return false
	end

	return true

end

function jq_IsWeaponAllowed(team, class, weapon)

	if class == CLASS_ENGINEER and team_maxriflegrenades > 0 and (weapon == WEAPON_K43 or weapon == WEAPON_GARAND) and jq_CountWeapons(team, weapon) >= team_maxriflegrenades then
		return false
	elseif class == CLASS_SOLDIER then
		if team_maxmortars > 0 and weapon == WEAPON_MORTAR and jq_CountWeapons(team, WEAPON_MORTAR) >= team_maxmortars then
			return false
		elseif team_maxpanzers > 0 and weapon == WEAPON_PANZERFAUST and jq_CountWeapons(team, WEAPON_PANZERFAUST) >= team_maxpanzers then
			return false
		elseif team_maxflamers > 0 and weapon == WEAPON_FLAMETHROWER and jq_CountWeapons(team, WEAPON_FLAMETHROWER) >= team_maxflamers then
			return false
		elseif team_maxmg42s > 0 and weapon == WEAPON_MG42 and jq_CountWeapons(team, WEAPON_MG42) >= team_maxmg42s then
			return false
		end
	end

	return true

end

function jq_CountWeapons(team, weapon)

	local count = 0

	for i = 0, sv_maxclients - 1 do

		if clients[i] ~= nil and clients[i].team == team then
			if tonumber(et.gentity_get(i, "sess.latchPlayerWeapon")) == weapon then
				count = count + 1
			end
		end

	end

	return count

end

function jq_Introduce(c)
	if introduction ~= nil then
		table.insert(futures, function()
			et.trap_SendServerCommand(c, "cp \"" .. introduction .. "\"\n")
		end)
	end
end

function jq_Banner(c)
	if banner ~= nil then
		table.insert(futures, function()
			et.trap_SendServerCommand(c, "chat \"" .. banner .. "\"\n")
		end)
	end
end

function jq_Shoutcaster(c, status)

	table.insert(futures, function()

		if status then
			if clients[c].team == 3 then
				shoutcast_announcement = true
				et.trap_SendConsoleCommand(et.EXEC_APPEND, "makeshoutcaster " .. c .. "\n")
			end
		else
			et.trap_SendConsoleCommand(et.EXEC_APPEND, "removeshoutcaster " .. c .. "\n")
		end

	end)

end

function jq_TellQueue(c)

	table.insert(futures, function()

		local list = ""
		local count = 0

		table.foreach(jq_GetQueue(-1), function(i, item)

			count = count + 1

			if item.queue_team == -1 then
				list = list .. "^7, ^7(" .. count .. ")^7 "
			elseif item.queue_team == 1 then
				list = list .. "^7, ^1(" .. count .. ")^7 "
			elseif item.queue_team == 2 then
				list = list .. "^7, ^4(" .. count .. ")^7 "
			end

			list = list .. item.name

		end)

		if count == 0 then
			list = "^7No players in queue."
		else
			list = "^7Queue: " .. string.sub(list, 5, string.len(list))
		end

		et.trap_SendServerCommand(c, "b 8 \"" .. list .. "\"\n")

	end)

end

-- credits: KMOD v1.5
function et.G_ClientSound(c, sound)
	local tempentity = et.G_TempEntity(et.gentity_get(c, "r.currentOrigin"), 54)
	et.gentity_set(tempentity, "s.teamNum", c)
	et.gentity_set(tempentity, "s.eventParm", sound)
end