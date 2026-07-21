-- scenarios/builders-vs-behemoth/control.lua -- launches Builders vs
-- Behemoth from "New Game -> Scenarios" (arena-generation change, design
-- D1). Mirrors the base game's own mod+scenario split
-- (base/scenarios/pvp/control.lua -> require('__base__/script/pvp/control.lua')):
-- require into the mode's activation entry point and call it, exactly once,
-- at this file's own scope. This is what actually wires every
-- `script.on_event`/`on_nth_tick`/`on_init` registration the mode needs
-- (scripts/main.lua) -- the mod's own top-level control.lua deliberately
-- does NOT do this, so a plain freeplay world with the mod enabled stays
-- vanilla.

local main = require("__builders-vs-behemoth__/scripts/main.lua")
main.activate()
