-- scripts/match.lua -- match lifecycle: forces, role selection, staggered
-- spawn, win/lose detection, match restart.
--
-- Module API convention: `on_init()` seeds `storage.match`; `on_load()`
-- touches no `game` state; the rest are event-entry-points named after the
-- Factorio event `control.lua` wires them to, plus a few plain helper
-- functions called from those entry points or from other modules.
--
-- Fills task group 2 (spec: match-lifecycle).

local economy = require("scripts.economy")
local defenses = require("scripts.defenses")
local behemoth = require("scripts.behemoth")
local shop = require("scripts.shop")

local M = {}

-- Tunables (placeholders; retune during the first balance pass, see
-- design.md "Open Questions" -- exact head-start delay/spawn layout are
-- explicitly called out as TBD numbers, not final).
local CONFIG = {
  behemoth_head_start_ticks = 35 * 60, -- ~35s (design.md: source mode is "~30-40s")
  surface_name = "nauvis",
  builder_spawn_position = { x = 0, y = 0 },
  behemoth_spawn_position = { x = 64, y = 0 }, -- offset so it doesn't stack on builders
  spawn_search_radius = 10,
  -- Items each Builder spawns with so the build-and-defend loop is reachable
  -- without a tech tree/starting-materials pipeline. Placeholder quantities;
  -- retune during the balance pass. Item names mirror the prototype/recipe
  -- names in prototypes/*.lua (intentional cross-stage duplication).
  builder_starter_kit = {
    { name = "bvb-generator", count = 1 }, -- placeable economy engine (one-per-builder enforced on placement)
    { name = "stone-brick", count = 50 }, -- Wall recipe costs 5 each (~10 walls)
    { name = "iron-gear-wheel", count = 50 }, -- Turret recipe costs 10 each (~5 turrets)
  },
}

-- GUI element names (namespaced with `bvb-` to stay out of other mods'/the
-- shop module's element-name space; see design D8/D9).
local ROLE_FRAME_NAME = "bvb-role-frame"
local ROLE_STATUS_LABEL_NAME = "bvb-role-status-label"
local ROLE_BUILDER_BUTTON_NAME = "bvb-role-builder-button"
local ROLE_BEHEMOTH_BUTTON_NAME = "bvb-role-behemoth-button"
local ROLE_START_BUTTON_NAME = "bvb-role-start-button"
local COUNTDOWN_LABEL_NAME = "bvb-countdown-label"
local END_FRAME_NAME = "bvb-end-frame"
local END_RESULT_LABEL_NAME = "bvb-end-result-label"
local END_RESTART_BUTTON_NAME = "bvb-end-restart-button"

-- Small local helpers (private; no other module needs these) ----------------

local function destroy_gui(player, name)
  local element = player.gui.screen[name]
  if element then
    element.destroy()
  end
end

-- Releases and destroys a player's current character (if any) so a fresh
-- one can be created at a new spawn point. Used for the lobby -> starting
-- transition and for restarts; also used to hold the Behemoth in spectator
-- mode during the head-start delay.
local function reset_character(player)
  local character = player.character
  if character then
    player.set_controller({ type = defines.controllers.spectator })
    if character.valid then
      character.destroy()
    end
  end
end

local function result_message_key(result)
  if result == "builders" then
    return "bvb-match.builders-win"
  end
  return "bvb-match.behemoth-wins"
end

-- Role-selection GUI (2.2) ----------------------------------------------------

local function refresh_role_status(player)
  local frame = player.gui.screen[ROLE_FRAME_NAME]
  if not frame then
    return
  end
  local label = frame[ROLE_STATUS_LABEL_NAME]
  if not label then
    return
  end
  local role = storage.match.role_votes[player.index]
  if role == "builder" then
    label.caption = { "bvb-match.role-status-builder" }
  elseif role == "behemoth" then
    label.caption = { "bvb-match.role-status-behemoth" }
  else
    label.caption = { "bvb-match.role-status-none" }
  end
end

local function show_role_gui(player)
  if player.gui.screen[ROLE_FRAME_NAME] then
    return
  end
  local frame = player.gui.screen.add({
    type = "frame",
    name = ROLE_FRAME_NAME,
    direction = "vertical",
    caption = { "bvb-match.role-selection-title" },
  })
  frame.auto_center = true
  frame.add({ type = "label", name = ROLE_STATUS_LABEL_NAME, caption = { "bvb-match.role-status-none" } })
  local button_flow = frame.add({ type = "flow", name = "bvb-role-button-flow", direction = "horizontal" })
  button_flow.add({ type = "button", name = ROLE_BUILDER_BUTTON_NAME, caption = { "bvb-match.role-builder" } })
  button_flow.add({ type = "button", name = ROLE_BEHEMOTH_BUTTON_NAME, caption = { "bvb-match.role-behemoth" } })
  frame.add({ type = "button", name = ROLE_START_BUTTON_NAME, caption = { "bvb-match.start-match" } })
end

local function close_role_gui_for_all()
  for _, player in pairs(game.connected_players) do
    destroy_gui(player, ROLE_FRAME_NAME)
  end
end

local function set_role_vote(player_index, role)
  if storage.match.phase ~= "lobby" then
    return
  end
  storage.match.role_votes[player_index] = role
  local player = game.get_player(player_index)
  if player then
    refresh_role_status(player)
  end
end

-- Staggered start (2.4) -------------------------------------------------------

local function show_countdown_label(player)
  if player.gui.screen[COUNTDOWN_LABEL_NAME] then
    return
  end
  player.gui.screen.add({ type = "label", name = COUNTDOWN_LABEL_NAME, caption = "" })
end

local function show_countdown_for_all()
  for _, player in pairs(game.connected_players) do
    show_countdown_label(player)
  end
end

local function update_countdown_labels(seconds_remaining)
  for _, player in pairs(game.connected_players) do
    local label = player.gui.screen[COUNTDOWN_LABEL_NAME]
    if label then
      label.caption = { "bvb-match.countdown", tostring(seconds_remaining) }
    end
  end
end

local function remove_countdown_labels()
  for _, player in pairs(game.connected_players) do
    destroy_gui(player, COUNTDOWN_LABEL_NAME)
  end
end

-- Creates a fresh character for `player` at `position` on the match surface
-- and switches their controller to it. Destroys any character the player
-- currently has first (covers both restarts and the base game's own
-- character handling) so match.lua is the single source of truth for
-- when/where builders and the Behemoth actually spawn.
local function spawn_character(player, position)
  reset_character(player)
  local surface = game.surfaces[CONFIG.surface_name] or game.surfaces[1]
  local spawn_position = surface.find_non_colliding_position("character", position, CONFIG.spawn_search_radius, 1)
    or position
  local character = surface.create_entity({ name = "character", position = spawn_position, force = player.force })
  player.set_controller({ type = defines.controllers.character, character = character })
end

-- Gives a freshly-spawned Builder the starter kit so they can immediately
-- place a Generator and hand-craft Walls/Turrets (no tech/materials pipeline
-- in the MVP). Inserts into the player's current character inventory.
local function grant_builder_starter_kit(player)
  if not player.character then
    return
  end
  for _, stack in ipairs(CONFIG.builder_starter_kit) do
    player.insert(stack)
  end
end

local function spawn_builder(player)
  spawn_character(player, CONFIG.builder_spawn_position)
  grant_builder_starter_kit(player)
end

local function spawn_behemoth(player)
  spawn_character(player, CONFIG.behemoth_spawn_position)
end

-- Holds the Behemoth player as a spectator (no character) for the
-- head-start delay so they cannot act while Builders scatter and hide.
local function hold_behemoth_waiting(player)
  reset_character(player)
  player.set_controller({ type = defines.controllers.spectator })
end

local function spawn_behemoth_now()
  storage.match.phase = "in_progress"
  local player = game.get_player(storage.match.behemoth_player_index)
  if player then
    spawn_behemoth(player)
  end
  remove_countdown_labels()
end

-- Match end / restart (2.6) ---------------------------------------------------

local function show_end_gui(player, result)
  if player.gui.screen[END_FRAME_NAME] then
    return
  end
  local frame = player.gui.screen.add({
    type = "frame",
    name = END_FRAME_NAME,
    direction = "vertical",
    caption = { "bvb-match.match-over-title" },
  })
  frame.auto_center = true
  frame.add({ type = "label", name = END_RESULT_LABEL_NAME, caption = { result_message_key(result) } })
  frame.add({ type = "button", name = END_RESTART_BUTTON_NAME, caption = { "bvb-match.new-match" } })
end

local function restart_match()
  for _, player in pairs(game.connected_players) do
    destroy_gui(player, END_FRAME_NAME)
  end
  -- Cross-module reset (each module owns and clears its own namespace, see
  -- design D3/D9) so leftover currency/generators/walls/turrets/render
  -- objects/force modifiers from the previous match never bleed into this
  -- one.
  economy.reset()
  defenses.reset()
  behemoth.reset()
  shop.reset()
  storage.match.phase = "lobby"
  storage.match.role_votes = {}
  storage.match.behemoth_player_index = nil
  storage.match.builder_player_indices = {}
  storage.match.start_tick = nil
  storage.match.behemoth_spawn_tick = nil
  storage.match.result = nil
  for _, player in pairs(game.connected_players) do
    show_role_gui(player)
  end
end

-- Match start trigger, invoked from the lobby GUI's Start button (2.1, 2.3,
-- 2.4) -------------------------------------------------------------------

local function start_match()
  if storage.match.phase ~= "lobby" then
    return
  end
  M.resolve_behemoth()
  if not storage.match.behemoth_player_index then
    return -- no connected players to start a match with
  end
  storage.match.phase = "starting"
  storage.match.start_tick = game.tick
  storage.match.behemoth_spawn_tick = game.tick + CONFIG.behemoth_head_start_ticks
  close_role_gui_for_all()
  for player_index in pairs(storage.match.builder_player_indices) do
    local player = game.get_player(player_index)
    if player then
      spawn_builder(player)
    end
  end
  local behemoth_player = game.get_player(storage.match.behemoth_player_index)
  if behemoth_player then
    hold_behemoth_waiting(behemoth_player)
  end
  show_countdown_for_all()
end

-- Module API entry points ----------------------------------------------------

function M.on_init()
  storage.match.phase = "lobby" -- lobby | starting | in_progress | ended
  storage.match.behemoth_player_index = nil
  storage.match.builder_player_indices = {} -- set: player_index -> true (living builders once resolved)
  storage.match.start_tick = nil
  storage.match.behemoth_spawn_tick = nil
  storage.match.result = nil
  storage.match.role_votes = {} -- role_votes[player_index] = "builder" | "behemoth", set during lobby
  M.setup_forces()
end

function M.on_load()
  -- No `game` access here. Nothing to re-wire yet.
end

-- Forces + role resolution (2.1, 2.3) ----------------------------------------

function M.setup_forces()
  local builders = game.forces.builders or game.create_force("builders")
  local behemoth_force = game.forces.behemoth or game.create_force("behemoth")
  -- Relations are unidirectional: set cease-fire off in BOTH directions so
  -- the forces are mutually hostile (design D2). All Builder players share
  -- the single `builders` force, so they're auto-allied with each other.
  builders.set_cease_fire(behemoth_force, false)
  behemoth_force.set_cease_fire(builders, false)
end

function M.resolve_behemoth()
  local connected = game.connected_players
  if #connected == 0 then
    return
  end

  local volunteers = {}
  for _, player in pairs(connected) do
    if storage.match.role_votes[player.index] == "behemoth" then
      volunteers[#volunteers + 1] = player.index
    end
  end

  local chosen_index
  if #volunteers > 0 then
    -- Exactly one Behemoth from the volunteers (spec: "Exactly one Behemoth
    -- is chosen"). math.random is deterministic/synchronized at runtime.
    chosen_index = volunteers[math.random(#volunteers)]
  else
    -- No volunteer: randomly designate one connected player (spec: "No
    -- Behemoth volunteer").
    chosen_index = connected[math.random(#connected)].index
  end

  storage.match.behemoth_player_index = chosen_index
  storage.match.builder_player_indices = {}
  local builders_force = game.forces.builders
  local behemoth_force = game.forces.behemoth
  for _, player in pairs(connected) do
    if player.index == chosen_index then
      player.force = behemoth_force
    else
      storage.match.builder_player_indices[player.index] = true
      player.force = builders_force
    end
  end
end

-- Player join flow (2.2) -----------------------------------------------------

function M.on_player_created(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  if storage.match.phase == "lobby" then
    show_role_gui(player)
  end
end

function M.on_player_joined_game(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  if storage.match.phase == "lobby" then
    if not storage.match.role_votes[event.player_index] then
      show_role_gui(player)
    end
  elseif storage.match.phase == "starting" then
    -- Reconnecting/late-joining mid-lobby-close: show the same countdown
    -- everyone else sees.
    show_countdown_label(player)
    local remaining = storage.match.behemoth_spawn_tick - game.tick
    local label = player.gui.screen[COUNTDOWN_LABEL_NAME]
    if label and remaining > 0 then
      label.caption = { "bvb-match.countdown", tostring(math.ceil(remaining / 60)) }
    end
  elseif storage.match.phase == "ended" then
    show_end_gui(player, storage.match.result)
  end
end

-- Staggered start (2.4) ------------------------------------------------------

function M.on_countdown_tick(_event)
  if storage.match.phase ~= "starting" then
    return
  end
  local remaining = storage.match.behemoth_spawn_tick - game.tick
  if remaining <= 0 then
    spawn_behemoth_now()
  else
    update_countdown_labels(math.ceil(remaining / 60))
  end
end

-- Win/lose detection (2.5, 2.6) -----------------------------------------------

function M.on_entity_died(event)
  if storage.match.phase ~= "in_progress" then
    return
  end
  local entity = event.entity
  if not (entity and entity.valid) then
    return
  end
  if entity.type ~= "character" or not entity.player then
    return
  end

  local player_index = entity.player.index
  if player_index == storage.match.behemoth_player_index then
    M.end_match("builders")
  elseif storage.match.builder_player_indices[player_index] then
    storage.match.builder_player_indices[player_index] = nil
    -- An eliminated builder must stop earning income too, or their
    -- Generator keeps producing currency for a player no longer in the
    -- match.
    economy.clear_player(player_index)
    -- Eliminated builders become spectators for the rest of the match; no
    -- auto-respawn (respawn roles are a later, non-MVP change).
    entity.player.set_controller({ type = defines.controllers.spectator })
    if next(storage.match.builder_player_indices) == nil then
      M.end_match("behemoth")
    end
  end
end

-- Disconnect handling (2.5, 2.6): without this, a disconnected Behemoth
-- leaves Builders unable to ever trigger a win (nothing kills their
-- character), and a disconnected last Builder leaves the Behemoth unable to
-- ever trigger a win either -- both make the win condition unreachable.
-- Wired from control.lua's on_player_left_game dispatch.

function M.on_player_left_game(event)
  if storage.match.phase ~= "in_progress" then
    return
  end

  local player_index = event.player_index
  if player_index == storage.match.behemoth_player_index then
    M.end_match("builders")
  elseif storage.match.builder_player_indices[player_index] then
    storage.match.builder_player_indices[player_index] = nil
    economy.clear_player(player_index)
    if next(storage.match.builder_player_indices) == nil then
      M.end_match("behemoth")
    end
  end
end

function M.end_match(result)
  if storage.match.phase == "ended" then
    return
  end
  storage.match.phase = "ended"
  storage.match.result = result
  remove_countdown_labels()
  game.print({ result_message_key(result) })
  for _, player in pairs(game.connected_players) do
    show_end_gui(player, result)
  end
end

-- GUI click dispatch (2.2, 2.6) -----------------------------------------------
-- Wired from control.lua's single on_gui_click handler alongside shop's own
-- dispatch (see control.lua); element names are namespaced so the two never
-- collide.

function M.on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end
  local name = element.name
  if name == ROLE_BUILDER_BUTTON_NAME then
    set_role_vote(event.player_index, "builder")
  elseif name == ROLE_BEHEMOTH_BUTTON_NAME then
    set_role_vote(event.player_index, "behemoth")
  elseif name == ROLE_START_BUTTON_NAME then
    start_match()
  elseif name == END_RESTART_BUTTON_NAME then
    restart_match()
  end
end

return M
