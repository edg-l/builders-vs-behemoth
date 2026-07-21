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
  -- Grace period: Builders spawn and act immediately; the Behemoth is held
  -- in spectator until this elapses, so Builders have time to scatter, find a
  -- spot, place a Generator and start walling. Matches the source mode (Probes
  -- vs Zealot 2 spawns the hunter after ~30-40s).
  behemoth_head_start_ticks = 35 * 60, -- ~35s (source mode: ~30-40s)
  surface_name = "nauvis",
  builder_spawn_position = { x = 0, y = 0 }, -- center of the Builder spawn ring, see spawn_builder
  -- Radius of the ring Builders are scattered around at match start (audit
  -- fix: previously every Builder spawned on top of each other at
  -- builder_spawn_position, both risking find_non_colliding_position
  -- failures and defeating the "scatter and hide" design). Placeholder;
  -- retune during the balance pass alongside the other spawn-layout numbers.
  builder_spawn_ring_radius = 20,
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

-- Iterates game.players (not game.connected_players), mirroring
-- shop.reset()'s convention, so a disconnected player's stale role-frame
-- doesn't linger and reappear confusingly on reconnect (audit fix).
local function close_role_gui_for_all()
  for _, player in pairs(game.players) do
    if player.valid then
      destroy_gui(player, ROLE_FRAME_NAME)
    end
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
-- when/where builders and the Behemoth actually spawn. Returns `true` on
-- success, or `false` if create_entity failed (e.g. no valid position could
-- be found) -- in that case the player is left without a character; callers
-- must not proceed to grant items/arm/print an "onboarding" message (audit
-- fix: previously a nil/invalid `character` was passed straight into
-- set_controller, which would error).
local function spawn_character(player, position)
  reset_character(player)
  local surface = game.surfaces[CONFIG.surface_name] or game.surfaces[1]
  local spawn_position = surface.find_non_colliding_position("character", position, CONFIG.spawn_search_radius, 1)
    or position
  local character = surface.create_entity({ name = "character", position = spawn_position, force = player.force })
  if not (character and character.valid) then
    player.print({ "bvb-match.spawn-failed" })
    return false
  end
  player.set_controller({ type = defines.controllers.character, character = character })
  return true
end

-- Computes the `index`-th of `count` evenly-spaced points around a circle of
-- `radius` centered on `center` (audit fix: gives each Builder a distinct
-- spawn point instead of all sharing one position). Index-based, not
-- random, so it stays deterministic/synchronized across peers.
local function ring_position(center, index, count, radius)
  local angle = (index - 1) * (2 * math.pi / count)
  return { x = center.x + radius * math.cos(angle), y = center.y + radius * math.sin(angle) }
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

-- Spawns the `ordinal`-th of `total` Builders at its own point around the
-- spawn ring (see ring_position above), then grants the starter kit and
-- prints the role's onboarding objective (audit fix: role objectives were
-- previously never communicated in-game).
local function spawn_builder(player, ordinal, total)
  local position = ring_position(CONFIG.builder_spawn_position, ordinal, total, CONFIG.builder_spawn_ring_radius)
  if spawn_character(player, position) then
    grant_builder_starter_kit(player)
    player.print({ "bvb-onboard.builder" })
  end
end

local function spawn_behemoth(player)
  return spawn_character(player, CONFIG.behemoth_spawn_position)
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
  if player and spawn_behemoth(player) then
    -- Arm immediately rather than waiting for the next on_equip_tick (audit
    -- fix: on_nth_tick(60) left the Behemoth unarmed for up to ~1s).
    behemoth.arm(storage.match.behemoth_player_index)
    player.print({ "bvb-onboard.behemoth" })
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
  -- Iterates game.players (not game.connected_players), mirroring
  -- shop.reset()'s convention, so a disconnected player's stale end-frame
  -- doesn't linger, AND (audit fix) resets every known player's force back
  -- to `player` and destroys any leftover character -- otherwise a
  -- Builder/Behemoth from the previous match would sit on a hostile force
  -- with a live character all through the next lobby.
  local player_force = game.forces.player
  for _, player in pairs(game.players) do
    if player.valid then
      destroy_gui(player, END_FRAME_NAME)
      reset_character(player)
      if player_force then
        player.force = player_force
      end
    end
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
  storage.match.eliminated = {}
  storage.match.start_tick = nil
  storage.match.behemoth_spawn_tick = nil
  storage.match.result = nil
  for _, player in pairs(game.connected_players) do
    show_role_gui(player)
  end
end

-- Neutralizes native enemies once at match start (audit fix) so a third
-- party (biters) can never damage Builder structures or hand either side a
-- win it didn't earn: peaceful mode stops biter aggression outright,
-- existing enemy-force entities are removed so none are already attacking,
-- expansion is disabled so new nests don't appear mid-match, and mutual
-- cease-fire (both directions) stops any that do exist from targeting
-- either the builders or behemoth force.
local function neutralize_enemies()
  local enemy_force = game.forces.enemy
  local builders_force = game.forces.builders
  local behemoth_force = game.forces.behemoth

  for _, surface in pairs(game.surfaces) do
    surface.peaceful_mode = true
    for _, entity in pairs(surface.find_entities_filtered({ force = "enemy" })) do
      if entity.valid then
        entity.destroy()
      end
    end
  end
  game.map_settings.enemy_expansion.enabled = false

  if enemy_force then
    if builders_force then
      enemy_force.set_cease_fire(builders_force, true)
      builders_force.set_cease_fire(enemy_force, true)
    end
    if behemoth_force then
      enemy_force.set_cease_fire(behemoth_force, true)
      behemoth_force.set_cease_fire(enemy_force, true)
    end
  end
end

-- Match start trigger, invoked from the lobby GUI's Start button (2.1, 2.3,
-- 2.4) -------------------------------------------------------------------

-- Anti-cheese: restrict each force to only the recipes its role is meant to
-- hand-craft, so players can't sidestep the intended loop by hand-crafting
-- arbitrary vanilla items (furnaces, vanilla turrets, labs, belts, etc.).
-- Builders may craft only the mod's structures (the Generator item is also
-- handed out directly; its recipe stays enabled for re-crafting after
-- salvage). The Behemoth crafts nothing -- it's script-armed.
local BUILDER_ALLOWED_RECIPES = {
  ["bvb-generator"] = true,
  ["bvb-wall-1"] = true,
  ["bvb-turret"] = true,
}

local function lock_force_recipes(force, allowed)
  for name, recipe in pairs(force.recipes) do
    recipe.enabled = allowed[name] == true
  end
end

local function start_match(clicker_player_index)
  if storage.match.phase ~= "lobby" then
    return
  end
  -- Require at least 2 connected players (so there's >=1 Builder besides
  -- the Behemoth) before resolving roles; otherwise leave the lobby/forces
  -- untouched and tell the clicker why (audit fix: 1-player soft-lock).
  if #game.connected_players < 2 then
    local clicker = game.get_player(clicker_player_index)
    if clicker then
      clicker.print({ "bvb-match.need-two-players" })
    end
    return
  end
  M.resolve_behemoth()
  if not storage.match.behemoth_player_index then
    return -- no connected players to start a match with
  end
  neutralize_enemies()
  -- Anti-cheese: lock each force to only its intended recipes.
  lock_force_recipes(game.forces.builders, BUILDER_ALLOWED_RECIPES)
  lock_force_recipes(game.forces.behemoth, {})
  storage.match.phase = "starting"
  storage.match.start_tick = game.tick
  storage.match.behemoth_spawn_tick = game.tick + CONFIG.behemoth_head_start_ticks
  close_role_gui_for_all()

  -- Sort player_indices for a deterministic ordinal (pairs() iteration order
  -- over storage.match.builder_player_indices isn't specified) so every peer
  -- computes the same ring positions (audit fix: distinct spawn points).
  local builder_indices = {}
  for player_index in pairs(storage.match.builder_player_indices) do
    builder_indices[#builder_indices + 1] = player_index
  end
  table.sort(builder_indices)
  local builder_count = #builder_indices
  for ordinal, player_index in ipairs(builder_indices) do
    local player = game.get_player(player_index)
    -- Skip a Builder who disconnected between resolve_behemoth() above and
    -- this loop (audit fix): a nil/disconnected player has no world
    -- presence to spawn a character for.
    if player and player.connected then
      spawn_builder(player, ordinal, builder_count)
    end
  end

  local behemoth_player = game.get_player(storage.match.behemoth_player_index)
  if behemoth_player and behemoth_player.connected then
    hold_behemoth_waiting(behemoth_player)
  end
  show_countdown_for_all()
end

-- Module API entry points ----------------------------------------------------

function M.on_init()
  storage.match.phase = "lobby" -- lobby | starting | in_progress | ended
  storage.match.behemoth_player_index = nil
  storage.match.builder_player_indices = {} -- set: player_index -> true (living builders once resolved)
  storage.match.eliminated = {} -- set: player_index -> true (behemoth-lost/builder-eliminated this match; see on_player_respawned)
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
  elseif storage.match.phase == "in_progress" then
    -- Late join mid-match (audit fix): there's no role left to hand out, so
    -- put the joiner in spectator rather than leaving them on the default
    -- force with a base-game character.
    player.set_controller({ type = defines.controllers.spectator })
    player.print({ "bvb-match.spectate-in-progress" })
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
    storage.match.eliminated[player_index] = true
    if shop.close_for_player then
      shop.close_for_player(player_index)
    end
    M.end_match("builders")
  elseif storage.match.builder_player_indices[player_index] then
    storage.match.builder_player_indices[player_index] = nil
    storage.match.eliminated[player_index] = true
    -- An eliminated builder must stop earning income too, or their
    -- Generator keeps producing currency for a player no longer in the
    -- match.
    economy.clear_player(player_index)
    if shop.close_for_player then
      shop.close_for_player(player_index)
    end
    -- Eliminated builders become spectators for the rest of the match; no
    -- auto-respawn (respawn roles are a later, non-MVP change). Recorded in
    -- storage.match.eliminated above so on_player_respawned (audit fix) can
    -- re-force spectator if the base game's own respawn flow races this.
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
  local player_index = event.player_index

  if storage.match.phase == "starting" then
    -- Disconnect during the countdown (audit fix), before the Behemoth has
    -- even spawned yet.
    if player_index == storage.match.behemoth_player_index then
      -- Ambiguous per audit brief; simplest correct recovery chosen: abort
      -- the whole match back to the lobby (reusing restart_match's full
      -- cross-module reset) rather than try to re-resolve a new Behemoth
      -- from Builders who already got their starter kit/spawn -- there is
      -- no well-defined "next" Behemoth to promote mid-countdown.
      restart_match()
    elseif storage.match.builder_player_indices[player_index] then
      storage.match.builder_player_indices[player_index] = nil
    end
    return
  end

  if storage.match.phase ~= "in_progress" then
    return
  end

  if player_index == storage.match.behemoth_player_index then
    storage.match.eliminated[player_index] = true
    if shop.close_for_player then
      shop.close_for_player(player_index)
    end
    M.end_match("builders")
  elseif storage.match.builder_player_indices[player_index] then
    storage.match.builder_player_indices[player_index] = nil
    storage.match.eliminated[player_index] = true
    economy.clear_player(player_index)
    if shop.close_for_player then
      shop.close_for_player(player_index)
    end
    if next(storage.match.builder_player_indices) == nil then
      M.end_match("behemoth")
    end
  end
end

-- Eliminated-builder respawn race (audit fix): the base game may offer an
-- eliminated player a "respawn" action before/around the moment
-- on_entity_died puts them in spectator above; if they take it, put them
-- straight back into spectator rather than let them re-enter play as a
-- fresh character on a match they're no longer part of. Wired from
-- control.lua's single-registrar pattern.

function M.on_player_respawned(event)
  local player_index = event.player_index
  if not storage.match.eliminated[player_index] then
    return
  end
  local player = game.get_player(player_index)
  if player then
    player.set_controller({ type = defines.controllers.spectator })
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
    start_match(event.player_index)
  elseif name == END_RESTART_BUTTON_NAME then
    restart_match()
  end
end

return M
