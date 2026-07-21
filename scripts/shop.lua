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
--
-- Shop/UX pass (post-MVP): three fixes layered on top of the above.
--
-- FIX A (single source of truth for costs/effects): the dead
-- `*_upgrade_costs` display-only arrays and inline tooltip literals are
-- gone. Tooltips now read economy.get_generator_tier_info(),
-- defenses.get_wall_tier_info()/get_turret_tier_info(), and
-- behemoth.get_stat_tier_info() -- small read-only accessors added to those
-- modules that return a NEW array copy of their own CONFIG's per-tier cost
-- (and, where available, effect) data. Currency is still deducted
-- exclusively by those same modules' upgrade_*/scanner_sweep functions;
-- this file never touches storage.currency directly.
--
-- FIX B (tooltips show effects, not just costs): each tile's tooltip now
-- has an optional third line (cost ladder, then effect ladder) built by the
-- tooltip_fn on each CONFIG item -- see "Small local helpers" below for why
-- tooltips are built lazily rather than baked into CONFIG at module-load
-- time. Turret has no effect line (see get_turret_tier_info's doc comment
-- in defenses.lua for why its damage-per-tier can't be sourced from an
-- accessor without a second source of truth).
--
-- FIX C (persistent top-of-screen balance label): a second, always-visible
-- label in `player.gui.top` (TOP_BALANCE_LABEL_NAME), separate from the
-- shop panel's own in-frame balance label, shown for any player currently
-- holding a role in an in-progress match (see in_match_role/
-- refresh_top_balance_label below). No new storage is needed -- visibility
-- and value are both derived fresh from storage.match/storage.currency on
-- every refresh, so it stays deterministic across peers without its own
-- persisted state.

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
-- Persistent top-of-screen balance readout (separate from the toggleable
-- shop panel above; see refresh_top_balance_label's doc comment below).
local TOP_BALANCE_LABEL_NAME = "bvb-shop-top-balance-label"

-- Small local helpers (private; build tooltips on demand) -------------------
--
-- Tooltips are built LAZILY (called from M.open()'s item loop, never at
-- module-load time) because defenses.get_wall_tier_info() reads the
-- `prototypes.entity` global, which is only safe to touch inside an event
-- handler, not while this file's `require`s run at control-stage load.
-- CONFIG below therefore stores a `tooltip_fn` per item (a plain function
-- reference; storing it has no side effects) instead of a precomputed
-- LocalisedString.

-- Builds the upgrade-cost-ladder line, reusing the existing 2-/3-tier
-- locale keys (only 2- and 3-cost ladders occur in this mod's current
-- data: costs excludes each item's free tier-1 baseline).
local function cost_line(costs)
  if #costs >= 3 then
    return { "bvb-shop.upgrade-cost-3", tostring(costs[1]), tostring(costs[2]), tostring(costs[3]) }
  end
  return { "bvb-shop.upgrade-cost-2", tostring(costs[1]), tostring(costs[2]) }
end

-- Builds a single-placeholder effect line (e.g. "Income per interval:
-- 5 / 10 / 18 / 30") from an arbitrary-length per-tier value ladder, so one
-- locale key per effect type covers every ladder length without needing
-- -2/-3/-4 key variants the way the cost ladder above does.
local function effect_line(effect_key, values)
  local parts = {}
  for i, value in ipairs(values) do
    parts[i] = tostring(value)
  end
  return { effect_key, table.concat(parts, " / ") }
end

-- Assembles the full tooltip: item name, then the cost ladder, then
-- (optionally) an effect ladder line. Passing a nil `effect_key` omits the
-- effect line entirely (used for Turret; see get_turret_tier_info's doc
-- comment in defenses.lua for why no damage-per-tier number is available).
local function upgrade_tooltip(name_locale, costs, effect_key, effect_values)
  if effect_key and effect_values and #effect_values > 0 then
    return { "", name_locale, "\n", cost_line(costs), "\n", effect_line(effect_key, effect_values) }
  end
  return { "", name_locale, "\n", cost_line(costs) }
end

-- Per-item tooltip builders (FIX A/B: pull cost + effect data from the
-- owning module's read-only accessor instead of duplicated literals) -------

local function generator_tooltip()
  local costs, incomes = {}, {}
  for _, tier_info in ipairs(economy.get_generator_tier_info()) do
    incomes[#incomes + 1] = tier_info.income_per_interval
    if tier_info.upgrade_cost > 0 then
      costs[#costs + 1] = tier_info.upgrade_cost
    end
  end
  return upgrade_tooltip({ "bvb-economy.generator-name" }, costs, "bvb-shop.effect-income", incomes)
end

local function wall_tooltip()
  local costs, healths = {}, {}
  for _, tier_info in ipairs(defenses.get_wall_tier_info()) do
    if tier_info.max_health then
      healths[#healths + 1] = tier_info.max_health
    end
    if tier_info.upgrade_cost > 0 then
      costs[#costs + 1] = tier_info.upgrade_cost
    end
  end
  return upgrade_tooltip({ "bvb-defenses.wall-name" }, costs, "bvb-shop.effect-hp", healths)
end

-- No effect line: Turret damage-per-tier isn't available from an accessor
-- (see defenses.get_turret_tier_info's doc comment); only the cost ladder
-- is shown, same as before this change.
local function turret_tooltip()
  local costs = {}
  for _, tier_info in ipairs(defenses.get_turret_tier_info()) do
    if tier_info.upgrade_cost > 0 then
      costs[#costs + 1] = tier_info.upgrade_cost
    end
  end
  return upgrade_tooltip({ "bvb-defenses.turret-name" }, costs, nil, nil)
end

local function stat_tooltip(name_locale, stat_name, effect_key)
  local costs, magnitudes = {}, {}
  for _, tier_info in ipairs(behemoth.get_stat_tier_info(stat_name)) do
    costs[#costs + 1] = tier_info.upgrade_cost
    magnitudes[#magnitudes + 1] = tier_info.magnitude
  end
  return upgrade_tooltip(name_locale, costs, effect_key, magnitudes)
end

local function scanner_sweep_tooltip()
  return { "", { "bvb-behemoth.scanner-sweep" }, "\n", { "bvb-shop.free-cooldown-gated" } }
end

-- Immutable module-level CONFIG (shop layout; tooltips built on demand) -----

local CONFIG = {
  builder_items = {
    {
      element_name = "bvb-shop-buy-generator",
      sprite = "item/bvb-generator",
      kind = "generator",
      tooltip_fn = generator_tooltip,
    },
    {
      element_name = "bvb-shop-buy-wall",
      sprite = "item/bvb-wall-1",
      kind = "wall",
      tooltip_fn = wall_tooltip,
    },
    {
      element_name = "bvb-shop-buy-turret",
      sprite = "item/bvb-turret",
      kind = "turret",
      tooltip_fn = turret_tooltip,
    },
  },

  behemoth_items = {
    {
      element_name = "bvb-shop-buy-damage",
      sprite = "virtual-signal/signal-red",
      kind = "stat",
      stat_name = "damage",
      tooltip_fn = function()
        return stat_tooltip({ "bvb-behemoth.stat-damage" }, "damage", "bvb-shop.effect-damage")
      end,
    },
    {
      element_name = "bvb-shop-buy-attack-speed",
      sprite = "virtual-signal/signal-yellow",
      kind = "stat",
      stat_name = "attack_speed",
      tooltip_fn = function()
        return stat_tooltip({ "bvb-behemoth.stat-attack-speed" }, "attack_speed", "bvb-shop.effect-generic")
      end,
    },
    {
      element_name = "bvb-shop-buy-armor",
      sprite = "virtual-signal/signal-blue",
      kind = "stat",
      stat_name = "armor",
      tooltip_fn = function()
        return stat_tooltip({ "bvb-behemoth.stat-armor" }, "armor", "bvb-shop.effect-generic")
      end,
    },
    {
      element_name = "bvb-shop-buy-max-health",
      sprite = "virtual-signal/signal-green",
      kind = "stat",
      stat_name = "max_health",
      tooltip_fn = function()
        return stat_tooltip({ "bvb-behemoth.stat-health" }, "max_health", "bvb-shop.effect-generic")
      end,
    },
    {
      element_name = "bvb-shop-buy-scanner-sweep",
      sprite = "virtual-signal/signal-info",
      kind = "scanner_sweep",
      tooltip_fn = scanner_sweep_tooltip,
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

-- Read-only lookup against `storage.match` (see get_role above), additionally
-- gated on the match actually being live (`phase == "in_progress"`) -- once
-- a match ends, the winning side's role membership lingers in
-- storage.match until the next restart_match (match.lua is read-only from
-- here), so gating on phase is what makes the persistent balance label
-- (FIX C) disappear promptly at match end rather than only at the next
-- restart.
local function in_match_role(player_index)
  if storage.match.phase ~= "in_progress" then
    return nil
  end
  return get_role(player_index)
end

local function notify_reason(player, reason)
  local key = REASON_MESSAGE_KEYS[reason] or "bvb-shop.reason-unknown"
  player.print({ key })
end

-- Persistent top-of-screen balance label (FIX C) -----------------------------
-- Separate from the shop panel's own in-frame balance label (BALANCE_LABEL_NAME
-- above): always visible in `player.gui.top` for any player currently
-- holding a role (Builder or Behemoth) in an in-progress match, regardless
-- of whether their shop panel is open. Spectators/lobby players never see
-- it (in_match_role returns nil for them). Single entry point handles
-- create/update/destroy based on current role state, so every caller below
-- (on_balance_tick, purchases, join flow, teardown) can just call this and
-- not duplicate the ensure/destroy branching.
local function refresh_top_balance_label(player)
  if not in_match_role(player.index) then
    local label = player.gui.top[TOP_BALANCE_LABEL_NAME]
    if label then
      label.destroy()
    end
    return
  end
  if not player.gui.top[TOP_BALANCE_LABEL_NAME] then
    player.gui.top.add({ type = "label", name = TOP_BALANCE_LABEL_NAME, caption = "" })
  end
  player.gui.top[TOP_BALANCE_LABEL_NAME].caption = { "bvb-shop.top-balance", tostring(economy.get_currency(player.index)) }
end

-- Called after every upgrade/ability attempt: refreshes the balance display
-- on success, or looks up and prints the rejection message on failure.
-- Never deducts/refunds anything itself -- the called API already did (or
-- deliberately didn't) that.
local function finish_purchase(player, ok, reason)
  if ok then
    M.refresh_balance(player)
    refresh_top_balance_label(player)
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

-- Full-module reset, invoked from match.lua's restart_match: destroys any
-- open shop frame AND the persistent top balance label (FIX C -- restart is
-- one of the two teardown points that check calls for) across every known
-- player, not just connected ones, so a disconnected player's leftover GUI
-- doesn't reappear stale next match, and re-seeds storage.shop. Guards every
-- step since a fresh/short-lived save may have no players or GUIs yet.

function M.reset()
  for _, player in pairs(game.players) do
    if player and player.valid then
      local frame = player.gui.screen[FRAME_NAME]
      if frame then
        frame.destroy()
      end
      local top_balance_label = player.gui.top[TOP_BALANCE_LABEL_NAME]
      if top_balance_label then
        top_balance_label.destroy()
      end
    end
  end
  storage.shop = {}
end

-- Player join flow: makes sure every player has the top-of-screen toggle
-- button, and (FIX C) shows/hides the persistent top balance label if a
-- match is already running and this player already holds a role (e.g.
-- reconnecting). Wired from control.lua alongside match.lua's own
-- on_player_created/on_player_joined_game handling (same
-- multi-module-per-event pattern already used for on_entity_died,
-- on_built_entity, and on_gui_click; see control.lua).

function M.on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then
    ensure_toggle_button(player)
    refresh_top_balance_label(player)
  end
end

function M.on_player_joined_game(event)
  local player = game.get_player(event.player_index)
  if player then
    ensure_toggle_button(player)
    refresh_top_balance_label(player)
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
        tooltip = item.tooltip_fn(),
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

-- Closes a player's shop frame by player_index (audit fix: called from
-- match.lua's elimination paths so an eliminated/disconnected player's shop
-- doesn't linger open). Thin wrapper around M.close, which takes a
-- LuaPlayer rather than an index. Also tears down the persistent top
-- balance label (FIX C) immediately where role membership has already been
-- cleared by the caller (e.g. an eliminated Builder); otherwise the next
-- on_balance_tick call (<=60 ticks later) removes it once
-- in_match_role/storage.match reflects the change.

function M.close_for_player(player_index)
  local player = game.get_player(player_index)
  if player and player.valid then
    M.close(player)
    refresh_top_balance_label(player)
  end
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
-- time this reads them) -- no new tick cadence is registered. Also drives
-- the persistent top balance label (FIX C) for every connected in-match
-- player regardless of whether their shop panel is open; this is the
-- cadence that creates the label shortly after a player is granted a role
-- and removes it shortly after they lose one (elimination, disconnect, or
-- match end), since match.lua (read-only from here) has no dedicated
-- role-granted/role-lost event to hook into directly.

function M.on_balance_tick(_event)
  for _, player in pairs(game.connected_players) do
    refresh_top_balance_label(player)
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
