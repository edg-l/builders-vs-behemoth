-- scripts/shop.lua -- the shared currency-spending GUI used by both roles.
--
-- Fills task group 7 (spec: shop-ui).

local M = {}

function M.on_init()
  -- storage.shop[player_index] = { frame_open = false }
end

function M.on_load()
  -- No `game` access here.
end

-- Panel (7.1) -----------------------------------------------------------------

function M.open(player)
  -- TODO(7.1): build a `player.gui.screen` frame of sprite-button tiles
  -- filtered by the player's role, with prices.
end

function M.close(player)
  -- TODO(7.1): destroy the shop frame for this player.
end

-- Balance label (7.2) ---------------------------------------------------------

function M.refresh_balance(player)
  -- TODO(7.2): update the live balance label bound to
  -- storage.currency[player.index].
end

-- Purchase dispatch (7.3, 7.4) ------------------------------------------------

function M.on_gui_click(event)
  -- TODO(7.3): dispatch on event.element.name; affordability check against
  -- storage.currency; deduct; refresh; reject + notify when unaffordable.
  -- TODO(7.4): wire purchases to economy.upgrade_generator,
  -- defenses.upgrade_wall / defenses.upgrade_turret,
  -- behemoth.upgrade_stat / behemoth.scanner_sweep.
end

return M
