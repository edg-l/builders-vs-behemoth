-- scripts/economy.lua -- builder economy: the Generator entity, its tier
-- ladder, and the currency income tick.
--
-- Owns `storage.currency` (shared counter keyed by player_index, used by
-- both builders and the Behemoth per design D3) and `storage.generators`.
--
-- Fills task group 3 (spec: builder-economy).

local M = {}

-- Tunables (placeholders; retune during the first balance pass, see
-- design.md "Open Questions" -- generator tier counts/costs/income are
-- explicitly called out as TBD numbers, not final).
local CONFIG = {
  generator_entity_name = "bvb-generator", -- prototypes/generator.lua
  generator_item_name = "bvb-generator",
  -- tiers[n] = { income_per_interval, upgrade_cost }. income_per_interval is
  -- credited once per economy.on_income_tick call (control.lua registers
  -- that on_nth_tick(60, ...), i.e. roughly once a second). upgrade_cost is
  -- the price to reach that tier from the previous one; tier 1 is the
  -- starting tier granted for free on placement.
  tiers = {
    [1] = { income_per_interval = 5, upgrade_cost = 0 },
    [2] = { income_per_interval = 10, upgrade_cost = 100 },
    [3] = { income_per_interval = 18, upgrade_cost = 250 },
    [4] = { income_per_interval = 30, upgrade_cost = 500 },
  },
}

-- Small local helpers (private; no other module needs these) ----------------

-- on_entity_died doesn't carry a player_index, so find the owning builder
-- by matching the dead entity's unit_number against the tracked Generator.
local function find_owner_by_unit_number(unit_number)
  for player_index, record in pairs(storage.generators) do
    if record.unit_number == unit_number then
      return player_index
    end
  end
  return nil
end

-- Module API entry points ----------------------------------------------------

function M.on_init()
  -- storage.currency[player_index] = balance
  -- storage.generators[player_index] = { entity = LuaEntity, tier = number, unit_number = number }
end

function M.on_load()
  -- No `game` access here.
end

-- Generator placement (3.1, 3.2) ---------------------------------------------

function M.on_built_entity(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == CONFIG.generator_entity_name) then
    return
  end
  local player_index = event.player_index
  if not player_index then
    -- No attributable Builder (e.g. script-raised placement with no
    -- player): nothing to track ownership against, so reject it outright.
    entity.destroy()
    return
  end
  if storage.generators[player_index] then
    -- Builder already has an active Generator: reject the placement,
    -- return the item, and notify (spec: "Only one Generator per Builder").
    local player = game.get_player(player_index)
    if player then
      player.insert({ name = CONFIG.generator_item_name, count = 1 })
      player.print({ "bvb-economy.generator-already-placed" })
    end
    entity.destroy()
    return
  end
  storage.generators[player_index] = { entity = entity, tier = 1, unit_number = entity.unit_number }
end

-- Salvage/refund (3.3) -------------------------------------------------------
-- The base game already returns the mined item to the player's inventory;
-- this only keeps storage.generators consistent so a builder can place a
-- new Generator elsewhere afterwards.

function M.on_player_mined_entity(event)
  local entity = event.entity
  if not (entity and entity.name == CONFIG.generator_entity_name) then
    return
  end
  local record = storage.generators[event.player_index]
  if record and record.unit_number == entity.unit_number then
    storage.generators[event.player_index] = nil
  end
end

-- Death cleanup (3.3), wired from control.lua's on_entity_died alongside
-- match.lua and defenses.lua -------------------------------------------------

function M.on_entity_died(event)
  local entity = event.entity
  if not (entity and entity.name == CONFIG.generator_entity_name) then
    return
  end
  local player_index = find_owner_by_unit_number(entity.unit_number)
  if player_index then
    storage.generators[player_index] = nil
  end
end

-- Tier upgrade (3.4), invoked from shop.lua purchase dispatch ----------------
-- Returns `true` on success, or `false, reason` on rejection (reason is one
-- of "no-generator", "max-tier", "insufficient-funds"). Notification is
-- shop.lua's job (task 7.3: "reject + notify when unaffordable"); this
-- function only enforces the rule and reports why, so callers other than
-- the shop can also drive it without duplicate messaging.

function M.upgrade_generator(player_index)
  local record = storage.generators[player_index]
  if not record then
    return false, "no-generator"
  end
  local next_tier = record.tier + 1
  local tier_stats = CONFIG.tiers[next_tier]
  if not tier_stats then
    return false, "max-tier"
  end
  local balance = M.get_currency(player_index)
  if balance < tier_stats.upgrade_cost then
    return false, "insufficient-funds"
  end
  storage.currency[player_index] = balance - tier_stats.upgrade_cost
  record.tier = next_tier
  return true
end

-- Currency income tick (3.5) -------------------------------------------------

function M.on_income_tick(_event)
  for player_index, record in pairs(storage.generators) do
    local tier_stats = CONFIG.tiers[record.tier]
    if tier_stats and record.entity and record.entity.valid then
      M.add_currency(player_index, tier_stats.income_per_interval)
    end
  end
end

-- Shared currency helpers (design D3: plain storage counters); behemoth.lua
-- and shop.lua read/write balances exclusively through these. ---------------

function M.get_currency(player_index)
  return storage.currency[player_index] or 0
end

function M.add_currency(player_index, amount)
  storage.currency[player_index] = (storage.currency[player_index] or 0) + amount
end

return M
