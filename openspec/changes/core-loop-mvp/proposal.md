## Why

Builders vs Behemoth has no code yet — only a validated concept and Factorio API mapping. We need a first playable slice that proves the asymmetric hide-build-hunt loop is *fun in Factorio's engine* before investing in the full tier trees, respawn roles, and multiple maps. This change delivers that MVP: one hunter versus many builders, with a working economy, defenses, hiding, a shop, and win/lose resolution.

## What Changes

- Introduce the mod skeleton: `info.json`, data stage, and a `control.lua` scenario entry point (multiplayer, `storage`-based, deterministic).
- Add a **role-selection + team setup** flow: on join, players pick Builder or Behemoth (exactly one Behemoth, chosen from volunteers/random); assign to two mutually-hostile forces.
- Add a **staggered match start**: builders spawn and scatter first, the Behemoth spawns after a delay, with win/lose detection (all builders dead → Behemoth wins; Behemoth dead → builders win) and match end.
- Add **builder economy**: a placeable Generator with a small tier ladder that drips currency via an income tick, scaled by tier.
- Add **builder defenses**: placeable Walls and Turrets on chokes, each with a shallow tier ladder (upgrade-in-place, single-HP-pool wall model, per-tier recolor).
- Add **Behemoth combat + progression**: currency earned from damage dealt to builder structures, spent at a central shop on stat upgrades (damage, attack speed, armor, HP), plus a **Scanner Sweep** reveal ability.
- Add **hiding + detection**: rely on Factorio fog of war so builder structures out of the Behemoth's live vision are hidden; the Behemoth reveals them by scouting or Scanner Sweep.
- Add a reusable **shop GUI** used by both sides to spend currency.

## Capabilities

### New Capabilities
- `match-lifecycle`: role selection, force creation and hostility, staggered spawn, win/lose detection, and match teardown/restart.
- `builder-economy`: the Generator entity, its tier ladder, and the currency income tick.
- `builder-defenses`: placeable Walls and Turrets, their tier ladders, upgrade-in-place, and per-tier visuals.
- `behemoth-combat`: damage-to-currency income, the stat-upgrade progression, and the Scanner Sweep ability.
- `hiding-vision`: fog-of-war-based concealment of builder structures and the rules for revealing them (vision range, Scanner Sweep).
- `shop-ui`: the shared currency-spending GUI framework (shop panel, buttons, purchase handling, balance display) used by both roles.

### Modified Capabilities
<!-- None — greenfield project, no existing specs. -->

## Impact

- **New code:** entire mod tree (`info.json`, `data.lua` / prototype files, `control.lua` + `scripts/`, `locale/`).
- **Factorio APIs used:** `LuaForce` (create_force, set_cease_fire, chart), `LuaSurface.create_entity`, `on_entity_damaged`, `on_nth_tick`, `LuaGuiElement` (`player.gui.screen`), `LuaRendering`, `LuaEntity` upgrade/replace. All state in `storage`; time from `game.tick`.
- **Dependencies:** base game only (Factorio 2.0). No Space Age dependency (Behemoth = base-game behemoth biter/large military entity). Custom prototypes require a data stage, so this ships as a **mod** (with an optional bundled scenario), not scenario-only.
- **Non-goals (deferred to later changes):** Hunter/Spirit respawn roles, multiple map variants, deep multi-tier economy/item trees, achievements/stats/ranks/leaderboards, custom art assets, AI-filled Behemoth.
- **Tuning caveat:** all numeric values (tier counts, costs, HP, income rates, spawn delay) are placeholders to be re-tuned for Factorio; the SC2 wiki numbers are not authoritative.
