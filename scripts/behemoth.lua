-- scripts/behemoth.lua -- Behemoth combat: damage-to-currency income, the
-- stat-upgrade progression, and the Scanner Sweep ability.
--
-- Fills task group 5 (spec: behemoth-combat).

local M = {}

function M.on_init()
  -- storage.behemoth = {
  --   player_index = nil,
  --   damage = 0, attack_speed = 0, armor = 0, max_health_bonus = 0,
  --   scanner_sweep_ready_tick = 0,
  -- }
end

function M.on_load()
  -- No `game` access here.
end

-- Behemoth entity (5.1) -------------------------------------------------------
-- Base entity choice and its upgradable stat definitions live alongside the
-- prototype definition (data stage); this module only applies runtime
-- upgrades to the spawned character/unit.

-- Damage-to-currency income (5.2) --------------------------------------------

function M.on_entity_damaged(event)
  -- TODO(5.2): filter event.entity.force.name == "builders"; award
  -- floor(event.final_damage_amount * rate) into storage.currency for the
  -- Behemoth's player_index.
end

-- Stat upgrades (5.3), invoked from shop.lua purchase dispatch ---------------

function M.upgrade_stat(stat_name)
  -- TODO(5.3): affordability check; apply damage/attack speed/armor/HP
  -- upgrade. HP upgrade must not drop current health below its pre-upgrade
  -- value.
end

-- Scanner Sweep (5.4) ---------------------------------------------------------

function M.scanner_sweep(target_position)
  -- TODO(5.4): enforce a cooldown via game.tick against
  -- storage.behemoth.scanner_sweep_ready_tick, then call
  -- vision.reveal_area(...) centered on target_position.
end

return M
