# Join queue Lua module for ET server

This module introduces a queue feature for ET servers. It lets players join the server and limit the number of players per team in the same time. Once the limit is reached, players are held in a queue (in order they have issued a team join command) and automatically put in the team they've chosen once there's a slot available.

Player can enter a queue by standard limbo menu and `/team` or referee command. That means that if ETAdmin is installed, `!axis` and `!allies` commands are automatically supported, as this internally leads to a server console `ref` command.

## Queues

There are three independent queues - axis, allies and *any*. Player can join by `/team r` or `/team b` (and limbo menu/ETAdmin command) to axis and allies queues respectively. Issuing `/team a` (or `ref putany` in server console - you can set this to your ETAdmin for a `!join` command, by the way) means that the player will be put in axis or allies team - whichever becomes available first.

Player can issue `/team a` always - even if there's an empty slot in both teams. The module will put such player in a team with less players.

Additional parameters of `team` command (class, weapon, alt. weapon) are supported and restored on team join.

Player can leave the queue by joining the spectator team (`/team s`, limbo menu or `!spec` eventually).

Every time there's a change in the queue, all players affected will be notified in chat area.

## Priority and overrides

Module supports *shrubbot* files. By default, `shrubbot.cfg` is read from mod directory, you can adjust the name using `jq_shrubbot` directive. Your shrubbot is supposed to define levels for players identified by GUID.

There are two directives affecting the queue - `jq_level_priority` and `jq_level_override`. Players with level equal and higher than `jq_level_priority` will always be put in front of the queue ahead of unprioritized players. Players with level equal and higher than `jq_level_override` will always be let to team and thus excluded from the queue completely.

Players connected using private password are always allowed to join a team anytime, just like with *override* level.

## Configuration

- `team_maxplayers [number]` - number of players per team
- `jq_shrubbot [filename]` - shrubbot file name (default: `shrubbot.cfg`)
- `jq_level_priority [number]` - prioritized levels
- `jq_level_override [number]` - overriding levels
- `jq_sound [filename]` - sound file to be played after joining a team from queue (e. g.: `sound/misc/skill_up.wav`)

Note that, internally, module changes `team_maxplayers` to `0` on game initialization and restores the original value on shutdown (end of round). This is a workaround for overrides and should cause no issues. However, **make sure this cvar is not locked**, that is, set it using `set team_maxplayers n` instead of `setl team_maxplayers n`.

If you use `globalcombinedfixes.lua` or any version of it, `/team a` or `/team r <more arguments>` command might not be working and issuing an invalid join command message instead. If this is the case, put `joinqueue.lua` **before** the `globalcombinedfixes.lua`, like this:

~~~
set lua_modules "joinqueue.lua globalcombined.lua"
~~~

This will make all commands working while preserving the exploit prevention.