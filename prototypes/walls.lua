-- prototypes/walls.lua -- the Wall entity's tier ladder (spec:
-- builder-defenses, task 4.1).
--
-- Unlike the Generator (single prototype + script-tracked tier; see
-- prototypes/generator.lua), the Wall's durability is engine-enforced
-- max_health baked into the prototype, not writable at runtime -- design
-- D5 documents the resulting upgrade path as scripted destroy+create_entity
-- at the same position, carrying the health ratio across, which requires
-- an actual higher-max_health prototype to create at the new tier. This is
-- therefore a genuine prototype-per-tier case: one "wall"-type prototype
-- per tier, all cloned from the base game's "stone-wall" graphics/collision.
--
-- Only tier 1 is directly placeable (item + recipe); tiers 2+ exist purely
-- as scripted upgrade targets (scripts/defenses.lua's upgrade_wall), so
-- their items are hidden/uncraftable -- entity.minable still needs a valid
-- item result, but nothing lets a player obtain one outside the upgrade
-- path. Tier>1 walls mine back into the TIER 1 item, not their own tier
-- (audit fix: re-placing a mined tier>1 Wall would otherwise recreate a
-- free tier>1 Wall, letting a Builder mine-and-replace to dodge the
-- upgrade_cost; re-placement is now always tier 1, so upgrades must be
-- re-paid). Tier 1 keeps mining into itself.
--
-- Placeholder values (max_health, upgrade_cost): TBD balance pass, see
-- design.md "Open Questions". Keep scripts/defenses.lua's
-- CONFIG.wall_tiers in sync with WALL_TIER_HEALTH below when retuning --
-- the data stage and runtime stage don't share Lua state, so this table
-- intentionally exists in both places.

local WALL_TIER_HEALTH = { 350, 700, 1400 }

for tier, max_health in ipairs(WALL_TIER_HEALTH) do
  local entity_name = "bvb-wall-" .. tier

  local wall_entity = table.deepcopy(data.raw["wall"]["stone-wall"])
  wall_entity.name = entity_name
  wall_entity.max_health = max_health
  wall_entity.minable = { mining_time = 0.5, result = tier == 1 and entity_name or "bvb-wall-1" }
  -- Audit fix: block blueprint capture/robot (re)construction so the
  -- storage.walls tracking in scripts/defenses.lua can't be bypassed;
  -- appended, not overwritten, so the base game's "placeable-neutral"/
  -- "player-creation" flags the clone carries are preserved. Hand-mining is
  -- unaffected -- it's governed by `minable` above, not by these flags.
  table.insert(wall_entity.flags, "not-blueprintable")
  table.insert(wall_entity.flags, "not-deconstructable")
  data:extend({ wall_entity })

  local wall_item = table.deepcopy(data.raw["item"]["stone-wall"])
  wall_item.name = entity_name
  wall_item.place_result = entity_name
  wall_item.order = entity_name
  if tier > 1 then
    wall_item.hidden = true -- not directly craftable; reached only via the scripted upgrade path
    wall_item.hidden_in_factoriopedia = true
  end
  data:extend({ wall_item })

  if tier == 1 then
    data:extend({
      {
        type = "recipe",
        name = entity_name,
        enabled = true, -- no technology gating for MVP; placeholder
        ingredients = { { type = "item", name = "stone-brick", amount = 5 } }, -- placeholder cost; TBD balance pass
        results = { { type = "item", name = entity_name, amount = 1 } },
      },
    })
  end
end
