-- luacheck config for Builders vs Behemoth.
--
-- No Factorio installation (and no factorio-luacheck plugin) on this dev
-- machine, so the runtime/data-stage API surface is declared by hand as
-- read-only globals: we only ever index into these (data.extend,
-- storage.currency = ..., script.on_init, defines.events, ...), never
-- reassign the top-level names themselves.

std = "lua52"

read_globals = {
  "data",       -- data-stage prototype table (data.lua, prototypes/*)
  "game",       -- runtime API root
  "storage",    -- persistent mod state (Factorio 2.0 replacement for `global`)
  "script",     -- event registration API
  "defines",    -- runtime constants (defines.events, defines.command, ...)
  "rendering",  -- LuaRendering (draw_sprite, etc.)
  "settings",   -- mod settings API
  "mods",
  "log",
  "table_size",
  "serpent",
}

-- Control/prototype files favor readable long lines over hard wrapping.
max_line_length = false
