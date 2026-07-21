-- scripts/shop.lua -- the shared currency-spending GUI used by both roles.
--
-- Fills task group 7 (spec: shop-ui).
--
-- Open/close (7.1): a plain text button in `player.gui.top` toggles a
-- `player.gui.screen` frame open/closed; the frame also carries its own
-- in-panel Close button. No custom-input/hotkey prototype is added -- the
-- task brief calls that optional ("e.g. a top-button toggle and/or a
-- hotkey"), and a single always-visible toggle button already satisfies
-- "provide a way to open/close it" without a new prototypes/ file or extra
-- control.lua event wiring. Open/closed state lives in
-- `storage.shop[player_index].open` (see M.on_init).
--
-- Role filtering (7.1): read-only lookup against `storage.match` (owned by
-- match.lua, not modified here) -- `behemoth_player_index` for the
-- Behemoth, `builder_player_indices` for Builders. A player with neither
-- (e.g. still in the lobby, or an eliminated/spectating builder) sees an
-- empty panel with a "no role yet" label instead of purchasable tiles.
--
-- Wall/Turret targeting (7.4): uses `player.selected` (the entity under the
-- player's world cursor) read FRESH at click time, never cached in
-- `storage.shop`. This is deliberate: `defenses.upgrade_wall` replaces the
-- Wall entity in place and returns a NEW unit_number on success (design D5)
-- -- because we never persist the old unit_number anywhere, the next click
-- simply re-resolves `player.selected` (recomputed by the engine from the
-- cursor's current world position, not the stale entity reference) and
-- transparently picks up the tiered-up entity at the same tile. Caveat
-- (flagged, not a defect): the player's cursor must still be hovering the
-- target Wall/Turret in the world at the moment they click the shop tile;
-- this cannot be verified without a running client, only reasoned about
-- from the documented API.
--
-- Scanner Sweep targeting (7.4): uses the Behemoth character's own current
-- world position (falling back to `player.position`) as `target_position`,
-- matching design D7/behemoth.lua's own suggestion ("MVP may sweep around
-- the Behemoth's own position").

local economy = require("scripts.economy")
local defenses = require("scripts.defenses")
local behemoth = require("scripts.behemoth")

local M = {}

-- GUI element names (namespaced with `bvb-shop-`, mirroring match.lua's
-- `bvb-role-`/`bvb-end-` convention so element names never collide across
-- modules sharing the single on_gui_click registration; see control.lua).
local FRAME_NAME = "bvb-shop-frame"
local TOGGLE_BUTTON_NAME = "bvb-shop-toggle-button"
local CLOSE_BUTTON_NAME = "bvb-shop-close-button"
local BALANCE_LABEL_NAME = "bvb-shop-balance-label"
local NO_ROLE_LABEL_NAME = "bvb-shop-no-role-label"
local ITEMS_FLOW_NAME = "bvb-shop-items-flow"

-- Small local helpers (private; build the immutable CONFIG below) ----------

-- Builds a two-line LocalisedString tooltip: the item's display name, then
-- its upgrade-cost ladder. `costs` is a plain array of upgrade_cost numbers
-- mirroring the owning module's tier table (see CONFIG's cost-list comment
-- below); only 2- and 3-tier ladders occur in this mod's current data.
local function upgrade_tooltip(name_locale, costs)
  local cost_line
  if #costs >= 3 then
    cost_line = { "bvb-shop.upgrade-cost-3", tostring(costs[1]), tostring(costs[2]), tostring(costs[3]) }
  else
    cost_line = { "bvb-shop.upgrade-cost-2", tostring(costs[1]), tostring(costs[2]) }
  end
  return { "", name_locale, "\n", cost_line }
end

-- Immutable module-level CONFIG (shop layout + display-only prices) --------
--
-- The `*_upgrade_costs` arrays are DISPLAY-ONLY copies of the
-- `upgrade_cost` values already authoritative in economy.lua's
-- CONFIG.tiers, defenses.lua's CONFIG.wall_tiers/turret_tiers, and
-- behemoth.lua's CONFIG.stat_tiers -- those tables are module-local, not
-- exported, so this mirrors the existing intentional-duplication
-- convention already used between the data stage and runtime stage (see
-- defenses.lua's wall_tier_by_entity_name / behemoth.lua's
-- builder_structure_names comments). KEEP IN SYNC with those modules'
-- upgrade_cost fields whenever retuning; the actual currency deduction
-- always comes from the authoritative module, never from this table.
local CONFIG = {
  generator_upgrade_costs = { 100, 250, 500 }, -- economy.lua CONFIG.tiers[2..4].upgrade_cost
  wall_upgrade_costs = { 150, 350 }, -- defenses.lua CONFIG.wall_tiers[2..3].upgrade_cost
  turret_upgrade_costs = { 200, 450 }, -- defenses.lua CONFIG.turret_tiers[2..3].upgrade_cost
  stat_upgrade_costs = { 100, 250, 500 }, -- behemoth.lua CONFIG.stat_tiers.*[1..3].upgrade_cost (same ladder for all four stats)

  builder_items = {
    {
      element_name = "bvb-shop-buy-generator",
      sprite = "item/bvb-generator",
      kind = "generator",
      tooltip = upgrade_tooltip({ "bvb-economy.generator-name" }, { 100, 250, 500 }),
    },
    {
      element_name = "bvb-shop-buy-wall",
      sprite = "item/bvb-wall-1",
      kind = "wall",
      tooltip = upgrade_tooltip({ "bvb-defenses.wall-name" }, { 150, 350 }),
    },
    {
      element_name = "bvb-shop-buy-turret",
      sprite = "item/bvb-turret",
      kind = "turret",
      tooltip = upgrade_tooltip({ "bvb-defenses.turret-name" }, { 200, 450 }),
    },
  },

  behemoth_items = {
    {
      element_name = "bvb-shop-buy-damage",
      sprite = "virtual-signal/signal-red",
      kind = "stat",
      stat_name = "damage",
      tooltip = upgrade_tooltip({ "bvb-behemoth.stat-damage" }, { 100, 250, 500 }),
    },
    {
      element_name = "bvb-shop-buy-attack-speed",
      sprite = "virtual-signal/signal-yellow",
      kind = "stat",
      stat_name = "attack_speed",
      tooltip = upgrade_tooltip({ "bvb-behemoth.stat-attack-speed" }, { 100, 250, 500 }),
    },
    {
      element_name = "bvb-shop-buy-armor",
      sprite = "virtual-signal/signal-blue",
      kind = "stat",
      stat_name = "armor",
      tooltip = upgrade_tooltip({ "bvb-behemoth.stat-armor" }, { 100, 250, 500 }),
    },
    {
      element_name = "bvb-shop-buy-max-health",
      sprite = "virtual-signal/signal-green",
      kind = "stat",
      stat_name = "max_health",
      tooltip = upgrade_tooltip({ "bvb-behemoth.stat-health" }, { 100, 250, 500 }),
    },
    {
      element_name = "bvb-shop-buy-scanner-sweep",
      sprite = "virtual-signal/signal-info",
      kind = "scanner_sweep",
      tooltip = { "", { "bvb-behemoth.scanner-sweep" }, "\n", { "bvb-shop.free-cooldown-gated" } },
    },
  },
}

-- Reverse lookups (element name -> item metadata) for O(1) on_gui_click
-- dispatch; derived once from CONFIG at module load, never mutated after.
local BUILDER_ITEM_BY_NAME = {}
for _, item in ipairs(CONFIG.builder_items) do
  BUILDER_ITEM_BY_NAME[item.element_name] = item
end
local BEHEMOTH_ITEM_BY_NAME = {}
for _, item in ipairs(CONFIG.behemoth_items) do
  BEHEMOTH_ITEM_BY_NAME[item.element_name] = item
end

-- Maps each upgrade function's failure `reason` string to the locale key
-- shop.lua prints -- this is the CENTRAL place rejection messages are
-- printed, since economy.lua/defenses.lua/behemoth.lua deliberately never
-- print (see their upgrade_*/scanner_sweep doc comments). Reuses existing
-- locale entries where a suitable one already exists (e.g. Scanner Sweep's
-- own cooldown message) instead of duplicating text.
local REASON_MESSAGE_KEYS = {
  ["no-generator"] = "bvb-shop.reason-no-generator",
  ["max-tier"] = "bvb-shop.reason-max-tier",
  ["insufficient-funds"] = "bvb-shop.insufficient-funds", -- existing key (locale/en/strings.cfg [bvb-shop])
  ["not-found"] = "bvb-shop.reason-not-found",
  ["create-failed"] = "bvb-shop.reason-create-failed",
  ["not-behemoth"] = "bvb-shop.reason-not-behemoth",
  ["unknown-stat"] = "bvb-shop.reason-unknown-stat",
  ["on-cooldown"] = "bvb-behemoth.scanner-sweep-on-cooldown", -- existing key (locale/en/strings.cfg [bvb-behemoth])
  ["no-target"] = "bvb-shop.reason-no-target",
}

-- Small local helpers (private) ----------------------------------------------

local function get_role(player_index)
  if player_index == storage.match.behemoth_player_index then
    return "behemoth"
  end
  if storage.match.builder_player_indices[player_index] then
    return "builder"
  end
  return nil
end

local function notify_reason(player, reason)
  local key = REASON_MESSAGE_KEYS[reason] or "bvb-shop.reason-unknown"
  player.print({ key })
end

-- Called after every upgrade/ability attempt: refreshes the balance display
-- on success, or looks up and prints the rejection message on failure.
-- Never deducts/refunds anything itself -- the called API already did (or
-- deliberately didn't) that.
local function finish_purchase(player, ok, reason)
  if ok then
    M.refresh_balance(player)
  else
    notify_reason(player, reason)
  end
end

local function ensure_toggle_button(player)
  if not player.gui.top[TOGGLE_BUTTON_NAME] then
    player.gui.top.add({
      type = "button",
      name = TOGGLE_BUTTON_NAME,
      caption = { "bvb-shop.shop-title" },
      tooltip = { "bvb-shop.toggle-tooltip" },
    })
  end
end

-- Builder purchases (7.4): generator has no world target (paid for by the
-- clicking player_index directly); wall/turret need `player.selected` (see
-- file header comment on targeting).
local function handle_builder_purchase(player, item)
  local player_index = player.index
  if item.kind == "generator" then
    local ok, reason = economy.upgrade_generator(player_index)
    finish_purchase(player, ok, reason)
    return
  end

  local target = player.selected
  if not (target and target.valid and target.unit_number) then
    finish_purchase(player, false, "no-target")
    return
  end

  if item.kind == "wall" then
    local ok, reason = defenses.upgrade_wall(player_index, target.unit_number)
    finish_purchase(player, ok, reason)
  elseif item.kind == "turret" then
    local ok, reason = defenses.upgrade_turret(player_index, target.unit_number)
    finish_purchase(player, ok, reason)
  end
end

-- Behemoth purchases (7.4): stat upgrades take no world target; Scanner
-- Sweep's target_position is the Behemoth character's own position (see
-- file header comment on targeting).
local function handle_behemoth_purchase(player, item)
  local player_index = player.index
  if item.kind == "stat" then
    local ok, reason = behemoth.upgrade_stat(player_index, item.stat_name)
    finish_purchase(player, ok, reason)
  elseif item.kind == "scanner_sweep" then
    local character = player.character
    local target_position = (character and character.valid) and character.position or player.position
    local ok, reason = behemoth.scanner_sweep(player_index, target_position)
    finish_purchase(player, ok, reason)
  end
end

function M.on_init()
  -- storage.shop[player_index] = { open = boolean }
end

function M.on_load()
  -- No `game` access here.
end

-- Player join flow: makes sure every player has the top-of-screen toggle
-- button. Wired from control.lua alongside match.lua's own
-- on_player_created/on_player_joined_game handling (same
-- multi-module-per-event pattern already used for on_entity_died,
-- on_built_entity, and on_gui_click; see control.lua).

function M.on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then
    ensure_toggle_button(player)
  end
end

function M.on_player_joined_game(event)
  local player = game.get_player(event.player_index)
  if player then
    ensure_toggle_button(player)
  end
end

-- Panel (7.1) -----------------------------------------------------------------

function M.open(player)
  if player.gui.screen[FRAME_NAME] then
    return
  end

  local role = get_role(player.index)
  local frame = player.gui.screen.add({
    type = "frame",
    name = FRAME_NAME,
    direction = "vertical",
    caption = { "bvb-shop.shop-title" },
  })
  frame.auto_center = true
  frame.add({ type = "label", name = BALANCE_LABEL_NAME, caption = "" })

  local items = nil
  if role == "builder" then
    items = CONFIG.builder_items
  elseif role == "behemoth" then
    items = CONFIG.behemoth_items
  end

  if items then
    local items_flow = frame.add({ type = "flow", name = ITEMS_FLOW_NAME, direction = "horizontal" })
    for _, item in ipairs(items) do
      items_flow.add({
        type = "sprite-button",
        name = item.element_name,
        sprite = item.sprite,
        tooltip = item.tooltip,
      })
    end
  else
    frame.add({ type = "label", name = NO_ROLE_LABEL_NAME, caption = { "bvb-shop.no-role" } })
  end

  frame.add({ type = "button", name = CLOSE_BUTTON_NAME, caption = { "bvb-shop.close" } })

  storage.shop[player.index] = storage.shop[player.index] or {}
  storage.shop[player.index].open = true
  M.refresh_balance(player)
end

function M.close(player)
  local frame = player.gui.screen[FRAME_NAME]
  if frame then
    frame.destroy()
  end
  storage.shop[player.index] = storage.shop[player.index] or {}
  storage.shop[player.index].open = false
end

function M.toggle(player)
  local state = storage.shop[player.index]
  if state and state.open then
    M.close(player)
  else
    M.open(player)
  end
end

-- Balance label (7.2) ---------------------------------------------------------

function M.refresh_balance(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not frame then
    return
  end
  local label = frame[BALANCE_LABEL_NAME]
  if not label then
    return
  end
  label.caption = { "bvb-shop.balance", tostring(economy.get_currency(player.index)) }
end

-- Periodic refresh for passive income (7.2), wired from control.lua's
-- existing on_nth_tick(60) cadence alongside economy.on_income_tick (which
-- runs first in that handler, so balances are already up to date by the
-- time this reads them) -- no new tick cadence is registered.

function M.on_balance_tick(_event)
  for _, player in pairs(game.connected_players) do
    local state = storage.shop[player.index]
    if state and state.open then
      M.refresh_balance(player)
    end
  end
end

-- Purchase dispatch (7.3, 7.4) ------------------------------------------------

function M.on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local name = element.name

  if name == TOGGLE_BUTTON_NAME then
    M.toggle(player)
    return
  end
  if name == CLOSE_BUTTON_NAME then
    M.close(player)
    return
  end

  local builder_item = BUILDER_ITEM_BY_NAME[name]
  if builder_item then
    handle_builder_purchase(player, builder_item)
    return
  end

  local behemoth_item = BEHEMOTH_ITEM_BY_NAME[name]
  if behemoth_item then
    handle_behemoth_purchase(player, behemoth_item)
  end
end

return M
