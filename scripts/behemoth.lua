-- scripts/behemoth.lua -- Behemoth combat: damage-to-currency income, the
-- stat-upgrade progression, and the Scanner Sweep ability.
--
-- Fills task group 5 (spec: behemoth-combat).

local economy = require("scripts.economy")
local vision = require("scripts.vision")

local M = {}

-- Tunables (placeholders; retune during the first balance pass, see
-- design.md "Open Questions" -- income rate, stat-tier costs/values, and
-- Scanner Sweep radius/cooldown are explicitly called out as TBD numbers,
-- not final).
--
-- Behemoth entity (5.1): match.lua already spawns the Behemoth player as a
-- vanilla "character" (see scripts/match.lua's spawn_behemoth/
-- spawn_character) -- the lowest-risk, already-controllable option, so this
-- module does NOT introduce a bespoke creature (biter/tank/spidertron, per
-- design.md's Open Question). It only arms that character with a
-- script-only weapon (prototypes/behemoth.lua) and applies stat upgrades to
-- it via LuaForce modifiers, so "the Behemoth's stats" really means "the
-- `behemoth` force's modifiers" (match.lua puts only the Behemoth player on
-- that force).
local CONFIG = {
  -- Weapon given to the Behemoth's character by on_equip_tick. Scoped to its
  -- own ammo_category (prototypes/behemoth.lua) so damage/attack-speed tier
  -- modifiers below never affect vanilla weapons or the Builders' Turrets
  -- (separate "bvb-turret-ammo" category; prototypes/turrets.lua).
  weapon_item_name = "bvb-behemoth-gun",
  ammo_item_name = "bvb-behemoth-ammo",
  weapon_ammo_category = "bvb-behemoth-weapon",
  ammo_refill_threshold = 50,
  ammo_refill_amount = 200,
  fallback_surface_name = "nauvis",

  -- Damage-to-currency income (5.2): 1 damage dealt to a Builder structure
  -- -> `income_rate` currency (design D4: "1 dmg -> 1 currency").
  income_rate = 1,

  -- The mod's own Builder STRUCTURE entity names (Generator, Wall tiers,
  -- Turret) -- the whitelist that defines "structure" for income purposes,
  -- deliberately excluding Builder characters and any neutral/terrain
  -- entity. Duplicated here rather than read from economy.lua/defenses.lua
  -- (whose entity-name tables are module-local CONFIG, not exported) --
  -- mirrors the existing intentional-duplication convention between the
  -- data stage and runtime stage (see prototypes/walls.lua,
  -- prototypes/turrets.lua); keep in sync with
  -- economy.lua's CONFIG.generator_entity_name and defenses.lua's
  -- CONFIG.wall_tier_by_entity_name / CONFIG.turret_entity_name when
  -- retuning.
  builder_structure_names = {
    ["bvb-generator"] = true,
    ["bvb-wall-1"] = true,
    ["bvb-wall-2"] = true,
    ["bvb-wall-3"] = true,
    ["bvb-turret"] = true,
  },

  -- Stat upgrades (5.3). Each stat has a finite tier ladder (mirrors
  -- economy.lua's/defenses.lua's tiers[n] shape); tier values are ABSOLUTE
  -- (the modifier/bonus to set when reaching that tier), not incremental.
  -- damage/attack_speed apply as LuaForce ammo/gun-speed modifiers scoped to
  -- CONFIG.weapon_ammo_category (same mechanism the base game's own combat
  -- techs use). armor has no native "damage taken" force modifier for
  -- characters, so it's applied by this module as a scripted flat
  -- damage-mitigation healback on hits the Behemoth's character takes (see
  -- `mitigate_armor_damage` below) -- report-flagged approximation, not a
  -- skip. max_health uses LuaForce.character_health_bonus (flat bonus over
  -- the character prototype's base max_health).
  stat_tiers = {
    damage = {
      [1] = { ammo_damage_modifier = 0.5, upgrade_cost = 100 },
      [2] = { ammo_damage_modifier = 1.0, upgrade_cost = 250 },
      [3] = { ammo_damage_modifier = 2.0, upgrade_cost = 500 },
    },
    attack_speed = {
      [1] = { gun_speed_modifier = 0.2, upgrade_cost = 100 },
      [2] = { gun_speed_modifier = 0.5, upgrade_cost = 250 },
      [3] = { gun_speed_modifier = 1.0, upgrade_cost = 500 },
    },
    armor = {
      [1] = { mitigation_bonus = 3, upgrade_cost = 100 },
      [2] = { mitigation_bonus = 6, upgrade_cost = 250 },
      [3] = { mitigation_bonus = 10, upgrade_cost = 500 },
    },
    max_health = {
      [1] = { health_bonus = 50, upgrade_cost = 100 },
      [2] = { health_bonus = 120, upgrade_cost = 250 },
      [3] = { health_bonus = 250, upgrade_cost = 500 },
    },
  },

  -- Scanner Sweep (5.4).
  scanner_sweep_cooldown_ticks = 45 * 60, -- ~45s placeholder
  scanner_sweep_radius = 15, -- tiles; placeholder
}

-- Small local helpers (private; no other module needs these) ----------------

-- Applies one stat tier's absolute value via the matching Factorio
-- mechanism (see CONFIG.stat_tiers comment above). Called only after
-- affordability/tier checks pass.
local function apply_stat_tier(stat_name, tier_stats)
  local force = game.forces.behemoth
  if stat_name == "damage" then
    force.set_ammo_damage_modifier(CONFIG.weapon_ammo_category, tier_stats.ammo_damage_modifier)
  elseif stat_name == "attack_speed" then
    force.set_gun_speed_modifier(CONFIG.weapon_ammo_category, tier_stats.gun_speed_modifier)
  elseif stat_name == "armor" then
    storage.behemoth.armor_mitigation = tier_stats.mitigation_bonus
  elseif stat_name == "max_health" then
    local player = game.get_player(storage.match.behemoth_player_index)
    local character = player and player.character
    local pre_health = (character and character.valid) and character.health or nil
    force.character_health_bonus = tier_stats.health_bonus
    -- Defensive: increasing max_health should never itself lower current
    -- health, but guard explicitly per spec ("must not drop current health
    -- below its pre-upgrade value").
    if pre_health and character.valid and character.health < pre_health then
      character.health = pre_health
    end
  end
end

-- Heals back part of a hit the Behemoth's character just took, scaled by
-- the current armor tier's flat mitigation_bonus (5.3's "armor" stat).
-- Never heals back more than was actually dealt, and never revives an
-- already-dead character.
local function mitigate_armor_damage(entity, final_damage_amount)
  local mitigation = storage.behemoth.armor_mitigation
  if not (mitigation and mitigation > 0) then
    return
  end
  if not (entity.valid and entity.health > 0) then
    return
  end
  local healback = math.min(mitigation, final_damage_amount)
  entity.health = math.min(entity.health + healback, entity.max_health)
end

function M.on_init()
  storage.behemoth.stat_tier = { damage = 0, attack_speed = 0, armor = 0, max_health = 0 }
  storage.behemoth.armor_mitigation = 0
  storage.behemoth.scanner_sweep_ready_tick = 0
end

function M.on_load()
  -- No `game` access here.
end

-- Behemoth entity (5.1) -------------------------------------------------------
-- Base entity choice (vanilla character, see CONFIG comment above) and the
-- weapon prototype it wields live in prototypes/behemoth.lua. This tick
-- keeps that character armed: called from control.lua's existing
-- on_nth_tick(60) cadence alongside economy.on_income_tick and
-- defenses.on_ammo_tick, so no new event registration is needed.

function M.on_equip_tick(event)
  local behemoth_player_index = storage.match.behemoth_player_index
  if not behemoth_player_index then
    return
  end
  local player = game.get_player(behemoth_player_index)
  local character = player and player.character
  if not (character and character.valid) then
    return
  end
  local gun_inventory = character.get_inventory(defines.inventory.character_guns)
  local ammo_inventory = character.get_inventory(defines.inventory.character_ammo)
  if not (gun_inventory and ammo_inventory) then
    return
  end
  if gun_inventory.get_item_count(CONFIG.weapon_item_name) == 0 then
    gun_inventory.insert({ name = CONFIG.weapon_item_name, count = 1 })
  end
  if ammo_inventory.get_item_count(CONFIG.ammo_item_name) < CONFIG.ammo_refill_threshold then
    ammo_inventory.insert({ name = CONFIG.ammo_item_name, count = CONFIG.ammo_refill_amount })
  end
end

-- Damage-to-currency income (5.2) --------------------------------------------
-- "Structure" is defined as membership in CONFIG.builder_structure_names
-- (Generator/Wall tiers/Turret), which already excludes Builder characters
-- and any neutral/terrain entity by construction (they're never in that
-- set); the `entity.force.name == "builders"` check on top of it excludes
-- everything not owned by the Builders force (design D4). Also feeds the
-- Behemoth's own armor mitigation (5.3) when the damaged entity is instead
-- the Behemoth's own character.

function M.on_entity_damaged(event)
  local entity = event.entity
  if not (entity and entity.valid) then
    return
  end

  if entity.force.name == "builders" and CONFIG.builder_structure_names[entity.name] then
    local behemoth_player_index = storage.match.behemoth_player_index
    if behemoth_player_index then
      economy.add_currency(behemoth_player_index, math.floor(event.final_damage_amount * CONFIG.income_rate))
    end
    return
  end

  if
    entity.type == "character"
    and entity.force.name == "behemoth"
    and entity.player
    and entity.player.index == storage.match.behemoth_player_index
  then
    mitigate_armor_damage(entity, event.final_damage_amount)
  end
end

-- Stat upgrades (5.3), invoked from shop.lua purchase dispatch ---------------
-- Signature: behemoth.upgrade_stat(player_index, stat_name), stat_name one
-- of "damage" | "attack_speed" | "armor" | "max_health". Returns `true` on
-- success, or `false, reason` on rejection (reason is one of "not-behemoth",
-- "unknown-stat", "max-tier", "insufficient-funds"); never prints (shop.lua
-- owns notification, matching economy.upgrade_generator/
-- defenses.upgrade_wall/upgrade_turret's convention).

function M.upgrade_stat(player_index, stat_name)
  if player_index ~= storage.match.behemoth_player_index then
    return false, "not-behemoth"
  end
  local tiers = CONFIG.stat_tiers[stat_name]
  if not tiers then
    return false, "unknown-stat"
  end
  local current_tier = storage.behemoth.stat_tier[stat_name] or 0
  local next_tier = current_tier + 1
  local tier_stats = tiers[next_tier]
  if not tier_stats then
    return false, "max-tier"
  end
  local balance = economy.get_currency(player_index)
  if balance < tier_stats.upgrade_cost then
    return false, "insufficient-funds"
  end

  economy.add_currency(player_index, -tier_stats.upgrade_cost)
  storage.behemoth.stat_tier[stat_name] = next_tier
  apply_stat_tier(stat_name, tier_stats)
  return true
end

-- Scanner Sweep (5.4) ---------------------------------------------------------
-- Signature: behemoth.scanner_sweep(player_index, target_position). Meant
-- to be invoked from shop.lua (a Scanner Sweep button/tile) or a future
-- custom-input hotkey bound to the Behemoth player; either caller passes
-- along its own player_index and a world position (e.g. the player's
-- cursor/character position). Returns `true` on success, or `false, reason`
-- on rejection ("not-behemoth", "on-cooldown"); never prints.
--
-- Depends on vision.reveal_area(force, surface, position, radius) (phase 6
-- owns its body; this is the agreed seam per scripts/vision.lua's existing
-- stub signature).

function M.scanner_sweep(player_index, target_position)
  if player_index ~= storage.match.behemoth_player_index then
    return false, "not-behemoth"
  end
  if game.tick < storage.behemoth.scanner_sweep_ready_tick then
    return false, "on-cooldown"
  end

  local player = game.get_player(player_index)
  local character = player and player.character
  local surface = (character and character.valid and character.surface)
    or game.surfaces[CONFIG.fallback_surface_name]
    or game.surfaces[1]

  vision.reveal_area(game.forces.behemoth, surface, target_position, CONFIG.scanner_sweep_radius)
  storage.behemoth.scanner_sweep_ready_tick = game.tick + CONFIG.scanner_sweep_cooldown_ticks
  return true
end

return M
