-- luacheck config for Builders vs Behemoth.
--
-- No Factorio installation (and no factorio-luacheck plugin) on this dev
-- machine, so the runtime/data-stage API surface is declared by hand.
-- `storage` and `game` are declared as MUTABLE globals (not read_globals):
-- both are legitimately written through at the top level (storage.currency
-- = ..., game.forces.behemoth.character_health_bonus = ...) as the whole
-- point of the runtime stage; the rest (data, script, defines, rendering,
-- settings, ...) are only ever called/indexed, never assigned into, so they
-- stay read-only. `table.deepcopy` is a Factorio-added stdlib extension
-- (data stage) not part of the declared `std`, so it's added as an extra
-- field on the existing `table` global.

std = "lua52"

globals = {
  "game",       -- runtime API root; written through (force/character fields)
  "storage",    -- persistent mod state (Factorio 2.0 replacement for `global`)
}

read_globals = {
  "data",       -- data-stage prototype table (data.lua, prototypes/*)
  "script",     -- event registration API
  "defines",    -- runtime constants (defines.events, defines.command, ...)
  "rendering",  -- LuaRendering (draw_sprite, etc.)
  "settings",   -- mod settings API
  "mods",
  "log",
  "table_size",
  "serpent",
  table = { fields = { "deepcopy" } }, -- Factorio stdlib extension (data stage)
}

-- Control/prototype files favor readable long lines over hard wrapping.
max_line_length = false
