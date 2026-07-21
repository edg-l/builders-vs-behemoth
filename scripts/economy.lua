-- scripts/economy.lua -- builder economy: the Generator entity, its tier
-- ladder, and the currency income tick.
--
-- Owns `storage.currency` (shared counter keyed by player_index, used by
-- both builders and the Behemoth per design D3) and `storage.generators`.
--
-- Fills task group 3 (spec: builder-economy).

local M = {}

function M.on_init()
  -- storage.currency[player_index] = balance
  -- storage.generators[player_index] = { entity = LuaEntity, tier = number }
end

function M.on_load()
  -- No `game` access here.
end

-- Generator placement (3.1, 3.2) ---------------------------------------------

function M.on_built_entity(event)
  -- TODO(3.2): enforce one active Generator per builder on placement;
  -- reject + notify on a second. Tier stat table from 3.1 lives alongside
  -- the Generator prototype definition.
end

-- Salvage/refund (3.3) -------------------------------------------------------

function M.on_player_mined_entity(event)
  -- TODO(3.3): refund on Generator removal so a builder can remove and
  -- re-place theirs.
end

-- Tier upgrade (3.4), invoked from shop.lua purchase dispatch ----------------

function M.upgrade_generator(player_index)
  -- TODO(3.4): affordability check against storage.currency; on success
  -- change the Generator's output rate for the new tier.
end

-- Currency income tick (3.5) -------------------------------------------------

function M.on_income_tick(event)
  -- TODO(3.5): credit each builder by their Generator's per-tick output
  -- into storage.currency[player_index].
end

-- Shared currency helpers (design D3: plain storage counters) ---------------

function M.get_balance(player_index)
  return storage.currency[player_index] or 0
end

function M.add_currency(player_index, amount)
  storage.currency[player_index] = (storage.currency[player_index] or 0) + amount
end

return M
