-- scripts/defenses.lua -- builder defenses: Walls and Turrets, their tier
-- ladders, upgrade-in-place, and per-tier visuals.
--
-- Fills task group 4 (spec: builder-defenses).

local economy = require("scripts.economy")

local M = {}

-- Tunables (placeholders; retune during the first balance pass, see
-- design.md "Open Questions" -- wall/turret tier counts, costs, and damage
-- are explicitly called out as TBD numbers, not final).
--
-- Walls: genuine prototype-per-tier (see prototypes/walls.lua) -- max_health
-- is engine-enforced from the prototype, not writable at runtime, so
-- tier-up is a scripted destroy+create_entity at the same position
-- (design D5), carrying the health ratio across.
--
-- Turrets: ONE shared entity prototype ("bvb-turret"), tier tracked here at
-- runtime -- mirrors the Generator's script-tracked-tier pattern. Per-tier
-- damage is baked into the AMMO item the turret is fed (prototypes/
-- turrets.lua), since that's where the engine enforces damage for an
-- ammo-turret; tier-up swaps the loaded ammo instead of recreating the
-- entity, so a Turret's unit_number stays stable across upgrades.
local CONFIG = {
  wall_tiers = {
    [1] = { entity_name = "bvb-wall-1", upgrade_cost = 0, tint = { r = 0.7, g = 0.7, b = 0.7, a = 1 } },
    [2] = { entity_name = "bvb-wall-2", upgrade_cost = 150, tint = { r = 0.3, g = 0.6, b = 1, a = 1 } },
    [3] = { entity_name = "bvb-wall-3", upgrade_cost = 350, tint = { r = 1, g = 0.55, b = 0.1, a = 1 } },
  },
  wall_tier_by_entity_name = {
    ["bvb-wall-1"] = 1,
    ["bvb-wall-2"] = 2,
    ["bvb-wall-3"] = 3,
  },
  -- Placeholder tintable icon for the per-tier recolor overlay (design D6);
  -- swap for bespoke tier-glow art in the balance pass.
  wall_overlay_sprite = "virtual-signal/signal-white",

  turret_entity_name = "bvb-turret",
  -- Damage lives solely in prototypes/turrets.lua's TURRET_TIER_DAMAGE (baked
  -- into each tier's ammo item); this table has no damage field to avoid two
  -- sources of truth for the same number.
  turret_tiers = {
    [1] = { ammo_item_name = "bvb-turret-ammo-1", upgrade_cost = 0 },
    [2] = { ammo_item_name = "bvb-turret-ammo-2", upgrade_cost = 200 },
    [3] = { ammo_item_name = "bvb-turret-ammo-3", upgrade_cost = 450 },
  },
  -- A Turret's ammo inventory is topped up (never fed by belts/inserters,
  -- design keeps it script-only) whenever its current ammo count drops
  -- below this threshold, refilling up to this amount.
  turret_ammo_refill_threshold = 50,
  turret_ammo_refill_amount = 200,
}

-- Small local helpers (private; no other module needs these) ----------------

-- Tops up a turret's ammo inventory with its current tier's ammo so it
-- never runs dry between control.lua's periodic on_ammo_tick calls.
-- Turrets never consume ammo via belts/inserters in this mod (design:
-- script-only supply), so this is the sole ammo source.
local function refill_turret_ammo(record)
  if not (record.entity and record.entity.valid) then
    return
  end
  local tier_stats = CONFIG.turret_tiers[record.tier]
  if not tier_stats then
    return
  end
  local inventory = record.entity.get_inventory(defines.inventory.turret_ammo)
  if not inventory then
    return
  end
  local current = inventory.get_item_count(tier_stats.ammo_item_name)
  if current < CONFIG.turret_ammo_refill_threshold then
    inventory.insert({ name = tier_stats.ammo_item_name, count = CONFIG.turret_ammo_refill_amount })
  end
end

function M.on_init()
  -- storage.walls[unit_number] = { entity = LuaEntity, tier = number, overlay = LuaRenderObject }
  -- storage.turrets[unit_number] = { entity = LuaEntity, tier = number }
end

function M.on_load()
  -- No `game` access here.
end

-- Placement (4.1, 4.2, 4.5) ---------------------------------------------------

function M.on_built_entity(event)
  local entity = event.entity
  if not (entity and entity.valid) then
    return
  end

  local wall_tier = CONFIG.wall_tier_by_entity_name[entity.name]
  if wall_tier then
    -- Single entity, one HP pool (spec: "Wall has a single health pool");
    -- storage.walls tracks it by unit_number so it blocks the Behemoth at
    -- chokes just by existing as solid collidable geometry.
    storage.walls[entity.unit_number] = { entity = entity, tier = wall_tier, overlay = nil }
    M.redraw_wall_overlay(entity.unit_number)
    return
  end

  if entity.name == CONFIG.turret_entity_name then
    -- Turret belongs to the placing player's force (builders); native force
    -- hostility (design D2, set up in match.lua) already restricts its
    -- targeting to Behemoth-force entities and never to builders, so no
    -- extra target filtering is needed here.
    storage.turrets[entity.unit_number] = { entity = entity, tier = 1 }
    refill_turret_ammo(storage.turrets[entity.unit_number])
  end
end

-- Death cleanup (supports 4.3, 4.4) ------------------------------------------

function M.on_entity_died(event)
  local entity = event.entity
  if not (entity and entity.unit_number) then
    return
  end

  local wall_record = storage.walls[entity.unit_number]
  if wall_record then
    if wall_record.overlay then
      wall_record.overlay.destroy()
    end
    storage.walls[entity.unit_number] = nil
    return
  end

  if storage.turrets[entity.unit_number] then
    storage.turrets[entity.unit_number] = nil
  end
end

-- Salvage cleanup, mirrors on_entity_died above but for a Wall/Turret being
-- MINED (base game already returns the item; this only keeps
-- storage.walls/storage.turrets consistent so the overlay render object
-- doesn't leak and the tile is free for a new placement) -------------------

function M.on_player_mined_entity(event)
  local entity = event.entity
  if not (entity and entity.unit_number) then
    return
  end

  local wall_record = storage.walls[entity.unit_number]
  if wall_record then
    if wall_record.overlay then
      wall_record.overlay.destroy()
    end
    storage.walls[entity.unit_number] = nil
    return
  end

  if storage.turrets[entity.unit_number] then
    storage.turrets[entity.unit_number] = nil
  end
end

-- Wall upgrade-in-place (4.3), invoked from shop.lua purchase dispatch -------
-- Signature: defenses.upgrade_wall(player_index, unit_number). Walls aren't
-- owned by a single builder (unlike the Generator), so the upgrade is paid
-- for by whichever player is acting in the shop, not the original placer.
-- Returns `true, new_unit_number` on success (the Wall's unit_number
-- changes because the tiered-up entity is a newly created one -- callers
-- must retarget any UI/selection to it), or `false, reason` on rejection
-- (reason is one of "not-found", "max-tier", "insufficient-funds");
-- shop.lua owns user notification, so this never prints.

function M.upgrade_wall(player_index, unit_number)
  local record = storage.walls[unit_number]
  if not (record and record.entity and record.entity.valid) then
    return false, "not-found"
  end

  local next_tier = record.tier + 1
  local tier_stats = CONFIG.wall_tiers[next_tier]
  if not tier_stats then
    return false, "max-tier"
  end

  local balance = economy.get_currency(player_index)
  if balance < tier_stats.upgrade_cost then
    return false, "insufficient-funds"
  end

  local old_entity = record.entity
  local health_ratio = old_entity.health / old_entity.max_health
  local surface = old_entity.surface
  local position = old_entity.position
  local force = old_entity.force
  local direction = old_entity.direction

  -- Create the new-tier entity FIRST, before touching the old one. If
  -- create_entity fails (e.g. something else occupies the tile in the
  -- instant between the checks above and here), the old Wall + its storage
  -- record are left completely untouched -- no gap in the choke, no zombie
  -- storage.walls entry, and no currency deducted.
  local new_entity = surface.create_entity({
    name = tier_stats.entity_name,
    position = position,
    force = force,
    direction = direction,
  })
  if not (new_entity and new_entity.valid) then
    return false, "create-failed"
  end
  new_entity.health = new_entity.max_health * health_ratio

  -- Only now destroy the old entity + its overlay; the new entity already
  -- exists at the same position, so the choke is never actually open to the
  -- Behemoth (spec: "no gap is opened").
  if record.overlay then
    record.overlay.destroy()
  end
  old_entity.destroy()

  economy.add_currency(player_index, -tier_stats.upgrade_cost)
  storage.walls[unit_number] = nil
  storage.walls[new_entity.unit_number] = { entity = new_entity, tier = next_tier, overlay = nil }
  M.redraw_wall_overlay(new_entity.unit_number)
  return true, new_entity.unit_number
end

-- Per-tier recolor overlay (4.4) ---------------------------------------------

function M.redraw_wall_overlay(unit_number)
  local record = storage.walls[unit_number]
  if not (record and record.entity and record.entity.valid) then
    return
  end
  if record.overlay then
    record.overlay.destroy()
    record.overlay = nil
  end
  local tier_stats = CONFIG.wall_tiers[record.tier]
  if not tier_stats then
    return
  end
  record.overlay = rendering.draw_sprite({
    sprite = CONFIG.wall_overlay_sprite,
    target = { entity = record.entity },
    tint = tier_stats.tint,
    surface = record.entity.surface,
  })
end

-- Turret upgrade (4.6), invoked from shop.lua purchase dispatch --------------
-- Signature: defenses.upgrade_turret(player_index, unit_number). Same
-- payer convention as upgrade_wall: the acting player in the shop pays,
-- not necessarily the Turret's placer. Unlike Walls, the Turret entity
-- itself is never recreated (see CONFIG comment above), so unit_number is
-- stable across upgrades. Returns `true` on success, or `false, reason`
-- ("not-found", "max-tier", "insufficient-funds"); never prints.

function M.upgrade_turret(player_index, unit_number)
  local record = storage.turrets[unit_number]
  if not (record and record.entity and record.entity.valid) then
    return false, "not-found"
  end

  local next_tier = record.tier + 1
  local tier_stats = CONFIG.turret_tiers[next_tier]
  if not tier_stats then
    return false, "max-tier"
  end

  local balance = economy.get_currency(player_index)
  if balance < tier_stats.upgrade_cost then
    return false, "insufficient-funds"
  end

  economy.add_currency(player_index, -tier_stats.upgrade_cost)
  record.tier = next_tier
  local inventory = record.entity.get_inventory(defines.inventory.turret_ammo)
  if inventory then
    inventory.clear() -- drop the previous tier's ammo before loading the new tier's
  end
  refill_turret_ammo(record)
  return true
end

-- Turret ammo top-up, wired from control.lua's existing 60-tick cadence
-- (alongside economy.on_income_tick) rather than registering a new
-- on_nth_tick cadence -------------------------------------------------------

function M.on_ammo_tick(_event)
  for _, record in pairs(storage.turrets) do
    refill_turret_ammo(record)
  end
end

-- Read-only tier accessors (design D3-adjacent: single source of truth for
-- shop.lua's tooltips, fixing the previous duplicated-cost-array problem).
-- Both return a NEW array (never a live CONFIG table) in tier order.
--
-- Wall max_health is read live from the actual entity prototype
-- (`game.entity_prototypes[entity_name].max_health`) rather than a
-- defenses.lua CONFIG mirror of prototypes/walls.lua's WALL_TIER_HEALTH --
-- no such mirror exists today, and adding one would be a THIRD source of
-- truth for the same number. Reading the live prototype instead is the
-- authoritative value by construction and can never drift out of sync.
--
-- Turret damage has no equivalent accessor: it's baked into each tier's
-- ammo item prototype's target_effects (prototypes/turrets.lua's
-- TURRET_TIER_DAMAGE), which isn't exposed as a simple runtime scalar the
-- way max_health is, and defenses.lua's CONFIG.turret_tiers deliberately
-- has no damage field (see its comment above) to avoid a second source of
-- truth. get_turret_tier_info() therefore only reports upgrade_cost;
-- shop.lua's turret tooltip has no per-tier damage effect line as a result
-- (reported in the shop-improvements task).

function M.get_wall_tier_info()
  local info = {}
  for tier, tier_stats in ipairs(CONFIG.wall_tiers) do
    local prototype = game and game.entity_prototypes[tier_stats.entity_name]
    info[tier] = {
      tier = tier,
      upgrade_cost = tier_stats.upgrade_cost,
      max_health = prototype and prototype.max_health or nil,
    }
  end
  return info
end

function M.get_turret_tier_info()
  local info = {}
  for tier, tier_stats in ipairs(CONFIG.turret_tiers) do
    info[tier] = { tier = tier, upgrade_cost = tier_stats.upgrade_cost }
  end
  return info
end

-- Full-module reset, invoked from match.lua's restart_match: destroys every
-- Wall (and its overlay) and Turret still standing so a new match starts
-- with a clean board rather than inheriting the previous match's defenses.

function M.reset()
  for _, record in pairs(storage.walls) do
    if record.overlay and record.overlay.valid then
      record.overlay.destroy()
    end
    if record.entity and record.entity.valid then
      record.entity.destroy()
    end
  end
  storage.walls = {}

  for _, record in pairs(storage.turrets) do
    if record.entity and record.entity.valid then
      record.entity.destroy()
    end
  end
  storage.turrets = {}
end

return M
