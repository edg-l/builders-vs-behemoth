-- scripts/main.lua -- mode activation entry point.
--
-- Owns every `on_init`/`on_load`/`script.on_event`/`on_nth_tick`
-- registration the mode's runtime needs. This used to live directly at the
-- top level of `control.lua`; it moved here (arena-generation change,
-- design D1) so a plain freeplay world with this mod enabled does NOT get
-- any of it -- the mod's top-level `control.lua` no longer calls
-- `M.activate()` on its own. Only two entry points call it:
--
--  - `scenarios/builders-vs-behemoth/control.lua` (the real launch path,
--    "New Game -> Scenarios"): requires this module and calls
--    `M.activate()` unconditionally at its own file scope, exactly once,
--    when that scenario's control.lua loads. Mirrors the base game's own
--    mod+scenario split (`base/scenarios/pvp/control.lua` ->
--    `require('__base__/script/pvp/control.lua')`).
--  - `control.lua`'s dev-only `/bvb-start` console command, so the mode can
--    be launched for manual testing without building/launching the bundled
--    scenario. NOT multiplayer-safe (a runtime console command fired by one
--    peer is not a synchronized game event) and not meant for real matches
--    -- a dev convenience only.
--
-- `M.activate()` is idempotent (guarded by the local `activated` flag)
-- so calling it twice -- e.g. a dev fires `/bvb-start` inside a game that
-- was already launched from the bundled scenario -- registers every
-- handler exactly once rather than double-dispatching events.
--
-- Everything below (the module list, storage namespaces, and every event
-- registration) is unchanged from the original top-level control.lua: only
-- the `require`s that pull them in and the wiring that registers them moved
-- into this file, behind `M.activate()`.

local match = require("scripts.match")
local economy = require("scripts.economy")
local defenses = require("scripts.defenses")
local behemoth = require("scripts.behemoth")
local vision = require("scripts.vision")
local shop = require("scripts.shop")
local arena = require("scripts.arena")

-- Single source of truth for the top-level `storage` namespaces this mod
-- uses (design D3/D9). Each module owns exactly one namespace and may add
-- nested structure to it from its own `on_init`.
local STORAGE_NAMESPACES = {
  "currency", -- economy.lua: storage.currency[player_index] = balance (builders and Behemoth alike)
  "match", -- match.lua: lifecycle/forces/spawn/win-lose state
  "generators", -- economy.lua: storage.generators[player_index] = { entity, tier }
  "walls", -- defenses.lua: storage.walls[unit_number] = { entity, tier, overlay }
  "turrets", -- defenses.lua: storage.turrets[unit_number] = { entity, tier }
  "behemoth", -- behemoth.lua: stats, upgrade levels, scanner sweep cooldown
  "vision", -- vision.lua: reveal-helper bookkeeping (active sweeps, etc.)
  "shop", -- shop.lua: per-player GUI state
  "arena", -- arena.lua: bounded surface + per-pocket boundary tracking (cliff entities / reverted tiles)
}

local MODULES = { match, economy, defenses, behemoth, vision, shop, arena }

local M = {}

local activated = false

function M.activate()
  if activated then
    return
  end
  activated = true

  script.on_init(function()
    for _, namespace in pairs(STORAGE_NAMESPACES) do
      storage[namespace] = storage[namespace] or {}
    end
    for _, module in pairs(MODULES) do
      if module.on_init then
        module.on_init()
      end
    end
  end)

  -- on_load MUST NOT touch `game` or mutate `storage`; it exists only to
  -- re-wire non-storage local state (e.g. metatables) if a module ever needs
  -- it. None do yet, but every module gets the hook for consistency.
  script.on_load(function()
    for _, module in pairs(MODULES) do
      if module.on_load then
        module.on_load()
      end
    end
  end)

  -- Match lifecycle (capability: match-lifecycle) ------------------------------

  -- Both match.lua (role-selection GUI) and shop.lua (top-of-screen shop
  -- toggle button; capability: shop-ui) need to react to a player showing up,
  -- so this fans out to both, matching the existing multi-module-per-event
  -- pattern used elsewhere in this file (see on_entity_died, on_built_entity,
  -- on_gui_click below).
  script.on_event(defines.events.on_player_created, function(event)
    match.on_player_created(event)
    shop.on_player_created(event)
  end)

  script.on_event(defines.events.on_player_joined_game, function(event)
    match.on_player_joined_game(event)
    shop.on_player_joined_game(event)
  end)

  script.on_event(defines.events.on_entity_died, function(event)
    match.on_entity_died(event)
    economy.on_entity_died(event)
    defenses.on_entity_died(event)
  end)

  -- Builder economy + defenses (capabilities: builder-economy, builder-defenses)

  script.on_event(defines.events.on_built_entity, function(event)
    economy.on_built_entity(event)
    defenses.on_built_entity(event)
  end)

  script.on_event(defines.events.on_player_mined_entity, function(event)
    economy.on_player_mined_entity(event)
    defenses.on_player_mined_entity(event)
  end)

  script.on_event(defines.events.on_player_left_game, function(event)
    match.on_player_left_game(event)
  end)

  -- Eliminated-builder respawn race (audit fix): re-forces spectator if the
  -- base game's own respawn flow puts an already-eliminated player back into
  -- a character (capability: match-lifecycle).
  script.on_event(defines.events.on_player_respawned, function(event)
    match.on_player_respawned(event)
  end)

  -- Behemoth combat (capability: behemoth-combat) ------------------------------

  script.on_event(defines.events.on_entity_damaged, function(event)
    behemoth.on_entity_damaged(event)
  end)

  -- Shop GUI (capability: shop-ui) ---------------------------------------------
  -- match.lua also owns GUI elements on this same event (role-selection,
  -- countdown, and match-end/restart buttons; capability: match-lifecycle);
  -- both dispatch off of `event.element.name`, which is namespaced per module,
  -- so a single shared `on_gui_click` registration fans out to both, matching
  -- the existing multi-module-per-event pattern used above.

  script.on_event(defines.events.on_gui_click, function(event)
    match.on_gui_click(event)
    shop.on_gui_click(event)
  end)

  -- Periodic ticks --------------------------------------------------------------
  -- One permanently-registered `on_nth_tick` per cadence; each handler
  -- branches internally on module-owned `storage` state rather than being
  -- added/removed at runtime.

  script.on_nth_tick(60, function(event)
    economy.on_income_tick(event)
    defenses.on_ammo_tick(event) -- tops up placed Turrets' ammo (builder-defenses 4.5/4.6)
    behemoth.on_equip_tick(event) -- arms/re-ammos the Behemoth's character (behemoth-combat 5.1/5.3)
    shop.on_balance_tick(event) -- refreshes any open shop's balance label after income (shop-ui 7.2); must run after economy.on_income_tick above
  end)

  script.on_nth_tick(30, function(event)
    match.on_countdown_tick(event)
  end)
end

return M
