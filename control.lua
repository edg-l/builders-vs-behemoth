-- control.lua -- mod-level runtime entry point for Builders vs Behemoth.
--
-- This mod's actual mode logic (all `on_init`/`on_load`/`script.on_event`/
-- `on_nth_tick` wiring -- see scripts/main.lua) is NOT activated here, so a
-- plain freeplay world with this mod enabled behaves like vanilla freeplay
-- (arena-generation change, design D1): no forces created, no
-- role-selection GUI, nothing hijacked -- this file registers nothing but
-- the dev command below.
--
-- The mode only activates when either:
--  - the bundled scenario is played: `scenarios/builders-vs-behemoth/control.lua`
--    requires `scripts/main.lua` and calls `main.activate()` at its own file
--    scope ("New Game -> Scenarios" is the intended launch path), or
--  - a player runs the dev-only `/bvb-start` command below, for manual
--    testing without building/launching the scenario (NOT multiplayer-safe;
--    dev convenience only -- see scripts/main.lua's own doc comment).

local main = require("scripts.main")

commands.add_command(
  "bvb-start",
  "Dev-only: activates the Builders vs Behemoth mode directly (skips launching the bundled scenario). Not multiplayer-safe; for manual testing only.",
  function(_command)
    main.activate()
  end
)
