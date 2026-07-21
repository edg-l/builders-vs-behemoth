-- prototypes/behemoth.lua -- the Behemoth's weapon (spec: behemoth-combat,
-- task 5.1).
--
-- Design decision (5.1, see design.md "Open Questions" -- Behemoth base
-- entity was explicitly left open): the Behemoth is the SAME vanilla
-- "character" entity match.lua already spawns for every player (see
-- scripts/match.lua's spawn_character) -- no bespoke controllable creature
-- (biter/tank/spidertron) is introduced, since match.lua's existing
-- character-based spawn/control flow is already correct and the lowest-risk
-- option. The only new prototype needed is a script-only weapon so that
-- character has something to fight with; its own ammo_category
-- ("bvb-behemoth-weapon") is scoped to the Behemoth alone so upgrading it
-- via LuaForce ammo/gun-speed modifiers (scripts/behemoth.lua) never
-- touches vanilla weapons or the Builders' Turrets (which use the separate
-- "bvb-turret-ammo" category; see prototypes/turrets.lua).
--
-- Both items are hidden and have no recipe: scripts/behemoth.lua's
-- on_equip_tick inserts them directly into the Behemoth character's gun/ammo
-- inventories, mirroring how prototypes/turrets.lua's ammo items are
-- script-managed only.
--
-- Placeholder value (BASE_DAMAGE): TBD balance pass, see design.md "Open
-- Questions". scripts/behemoth.lua's damage-tier modifiers
-- (force.set_ammo_damage_modifier) scale this base value multiplicatively,
-- so retuning the base amount here still composes with the runtime tiers.

local BASE_DAMAGE = 15

data:extend({
  {
    type = "ammo-category",
    name = "bvb-behemoth-weapon",
  },
})

local behemoth_gun = table.deepcopy(data.raw["gun"]["pistol"])
behemoth_gun.name = "bvb-behemoth-gun"
behemoth_gun.flags = { "hidden" } -- script-managed only; never craftable or hand-loadable
behemoth_gun.attack_parameters.ammo_category = "bvb-behemoth-weapon"
data:extend({ behemoth_gun })

data:extend({
  {
    type = "ammo",
    name = "bvb-behemoth-ammo",
    icon = "__base__/graphics/icons/firearm-magazine.png", -- placeholder art; reuses a vanilla icon
    icon_size = 64,
    subgroup = "ammo",
    order = "bvb-behemoth-ammo",
    stack_size = 200,
    flags = { "hidden" }, -- script-managed only; never craftable or hand-loadable
    ammo_type = {
      category = "bvb-behemoth-weapon",
      target_type = "entity",
      action = {
        type = "direct",
        action_delivery = {
          type = "instant",
          target_effects = {
            { type = "damage", damage = { amount = BASE_DAMAGE, type = "physical" } },
          },
        },
      },
    },
  },
})
