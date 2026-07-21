-- prototypes/turrets.lua -- the Turret entity and its ammo-driven tier
-- ladder (spec: builder-defenses, task 4.1).
--
-- Unlike the Wall (genuine prototype-per-tier, see prototypes/walls.lua),
-- the Turret entity itself stays a SINGLE shared prototype -- tier is
-- tracked at runtime in storage.turrets, mirroring the Generator's
-- script-tracked-tier pattern (see prototypes/generator.lua). What IS
-- engine-enforced per-tier is the turret's DAMAGE, and that lives in the
-- ammo item it fires, not in the turret prototype itself -- so the genuine
-- prototype-per-tier need here is scoped to the ammo, not the turret.
-- scripts/defenses.lua's upgrade_turret swaps the loaded ammo item on
-- tier-up rather than destroying/recreating the turret entity, so a
-- Turret's unit_number stays stable across upgrades.
--
-- Cloned from the base game's "gun-turret" (ammo-turret type) so it needs
-- no bespoke attack/graphics authoring; a dedicated "bvb-turret-ammo" ammo
-- category keeps it from also accepting vanilla bullets (and keeps vanilla
-- turrets from accepting ours). Each tier's ammo uses an "instant" trigger
-- delivery (target_effects applied directly, no extra projectile/beam
-- sub-prototype to author or reference) so the only per-tier field that
-- changes is the damage amount below. Ammo items are script-managed only
-- (scripts/defenses.lua tops up a turret's ammo inventory directly via
-- LuaInventory.insert), so they're flagged hidden and never craftable.
--
-- Placeholder values (damage, upgrade_cost, ammo counts): TBD balance
-- pass, see design.md "Open Questions". Keep scripts/defenses.lua's
-- CONFIG.turret_tiers damage numbers in sync with TURRET_TIER_DAMAGE below
-- when retuning -- the data stage and runtime stage don't share Lua state,
-- so this table intentionally exists in both places.

local TURRET_TIER_DAMAGE = { 20, 45, 90 }

data:extend({
  {
    type = "ammo-category",
    name = "bvb-turret-ammo",
  },
})

local turret_entity = table.deepcopy(data.raw["ammo-turret"]["gun-turret"])
turret_entity.name = "bvb-turret"
turret_entity.attack_parameters.ammo_category = "bvb-turret-ammo"
data:extend({ turret_entity })

local turret_item = table.deepcopy(data.raw["item"]["gun-turret"])
turret_item.name = "bvb-turret"
turret_item.place_result = "bvb-turret"
turret_item.order = "bvb-turret"
data:extend({ turret_item })

data:extend({
  {
    type = "recipe",
    name = "bvb-turret",
    enabled = true, -- no technology gating for MVP; placeholder
    ingredients = { { type = "item", name = "iron-gear-wheel", amount = 10 } }, -- placeholder cost; TBD balance pass
    results = { { type = "item", name = "bvb-turret", amount = 1 } },
  },
})

for tier, damage in ipairs(TURRET_TIER_DAMAGE) do
  local ammo_name = "bvb-turret-ammo-" .. tier
  data:extend({
    {
      type = "ammo",
      name = ammo_name,
      icon = "__base__/graphics/icons/firearm-magazine.png", -- placeholder art; reuses a vanilla icon
      icon_size = 64,
      subgroup = "ammo",
      order = "bvb-turret-ammo-" .. tier,
      stack_size = 200,
      flags = { "hidden" }, -- script-managed only; never craftable or hand-loadable
      ammo_type = {
        category = "bvb-turret-ammo",
        target_type = "entity",
        action = {
          type = "direct",
          action_delivery = {
            type = "instant",
            target_effects = {
              { type = "damage", damage = { amount = damage, type = "physical" } },
            },
          },
        },
      },
    },
  })
end
