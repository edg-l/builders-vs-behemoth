-- scripts/defenses.lua -- builder defenses: Walls and Turrets, their tier
-- ladders, upgrade-in-place, and per-tier visuals.
--
-- Fills task group 4 (spec: builder-defenses).

local M = {}

function M.on_init()
  -- storage.walls[unit_number] = { entity = LuaEntity, tier = number, overlay = LuaRenderObject }
  -- storage.turrets[unit_number] = { entity = LuaEntity, tier = number }
end

function M.on_load()
  -- No `game` access here.
end

-- Placement (4.1, 4.2, 4.5) ---------------------------------------------------

function M.on_built_entity(event)
  -- TODO(4.2): register a placed Wall (single entity, one HP pool) into
  -- storage.walls so it blocks the Behemoth at chokes.
  -- TODO(4.5): register a placed Turret into storage.turrets; native force
  -- hostility already restricts it to firing on Behemoth-force entities,
  -- never on builders.
end

-- Death cleanup (supports 4.3, 4.4) ------------------------------------------

function M.on_entity_died(event)
  -- TODO: drop the wall/turret's storage entry and destroy its recolor
  -- overlay (LuaRenderObject), if any, when the entity dies.
end

-- Wall upgrade-in-place (4.3), invoked from shop.lua purchase dispatch -------

function M.upgrade_wall(unit_number)
  -- TODO(4.3): apply_upgrade/next_upgrade where possible, else scripted
  -- destroy+create_entity at the same position carrying over the health
  -- ratio. Must not open a gap in the choke.
end

-- Per-tier recolor overlay (4.4) ---------------------------------------------

function M.redraw_wall_overlay(unit_number)
  -- TODO(4.4): destroy the previous LuaRenderObject (if any) and draw a new
  -- tinted rendering.draw_sprite overlay for the wall's current tier.
end

-- Turret upgrade (4.6), invoked from shop.lua purchase dispatch --------------

function M.upgrade_turret(unit_number)
  -- TODO(4.6): affordability check; increase damage for the new tier.
end

return M
