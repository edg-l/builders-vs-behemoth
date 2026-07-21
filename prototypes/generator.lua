-- prototypes/generator.lua -- the Generator entity Builders place to farm
-- currency over time (spec: builder-economy, task 3.1).
--
-- Single entity prototype: per-tier output is NOT modeled via swapped
-- prototypes. Tier is tracked at runtime in storage.generators, and the
-- tier -> output/upgrade-cost table lives in scripts/economy.lua next to
-- the code that reads it. This mirrors the Wall pattern (design D5/D6: one
-- entity, tier as script-tracked data) so a later tuning pass only touches
-- one table, not N prototypes.
--
-- Cloned from the base "steel-chest" container: gives health, minability,
-- and item-based placement for free without authoring custom graphics.
-- TBD/placeholder: swap in bespoke Generator art + a real recipe cost
-- during the first balance pass (design.md "Open Questions" flags all
-- numbers -- health, recipe cost, tier stats -- as placeholders to retune).

local generator_entity = table.deepcopy(data.raw["container"]["steel-chest"])
generator_entity.name = "bvb-generator"
generator_entity.minable = { mining_time = 0.5, result = "bvb-generator" }
generator_entity.max_health = 200 -- placeholder; TBD balance pass

local generator_item = table.deepcopy(data.raw["item"]["steel-chest"])
generator_item.name = "bvb-generator"
generator_item.place_result = "bvb-generator"
generator_item.order = "bvb-generator"

local generator_recipe = {
  type = "recipe",
  name = "bvb-generator",
  enabled = true, -- no technology gating for MVP; placeholder
  ingredients = { { type = "item", name = "iron-plate", amount = 20 } }, -- placeholder cost; TBD balance pass
  results = { { type = "item", name = "bvb-generator", amount = 1 } },
}

data:extend({ generator_entity, generator_item, generator_recipe })
