## 1. Mod skeleton and tooling

- [x] 1.1 Create `info.json` (name `builders-vs-behemoth`, factorio_version 2.0, base dependency, version 0.1.0)
- [x] 1.2 Create stub `data.lua`, `control.lua`, and `scripts/` directory; wire `control.lua` to require each module
- [x] 1.3 Add `locale/en/strings.cfg` for entity/GUI/message text
- [x] 1.4 Add `.luacheckrc` declaring Factorio globals (`data`, `game`, `storage`, `script`, `defines`, `rendering`, `settings`) and add a static-check command to README
- [x] 1.5 Initialize `storage` namespaces in `script.on_init` and a no-`game` `script.on_load`

## 2. Match lifecycle (spec: match-lifecycle)

- [x] 2.1 Define `builders` and `behemoth` forces at match start; set `set_cease_fire(other, false)` in BOTH directions
- [x] 2.2 Implement role-selection GUI on `on_player_joined_game`/`on_player_created` (Builder / Behemoth)
- [x] 2.3 Resolve exactly one Behemoth (from volunteers, else random connected player); assign all others to `builders`
- [x] 2.4 Implement staggered start: builders spawn immediately, Behemoth spawns after a configurable head-start delay with an on-screen countdown (`game.tick`-based)
- [x] 2.5 Track living builders and the Behemoth; on `on_entity_died`/player elimination detect win/lose (all builders dead → Behemoth wins; Behemoth dead → builders win)
- [x] 2.6 Announce result to all players and offer/restart a new match on match end

## 3. Builder economy (spec: builder-economy)

- [x] 3.1 Define the Generator entity prototype and its tier stat table (output per tier, upgrade costs)
- [x] 3.2 Enforce one active Generator per builder on placement (`on_built_entity`); reject + notify on a second
- [x] 3.3 Implement salvage/refund so a builder can remove and re-place their Generator
- [x] 3.4 Implement Generator tier upgrade with affordability check and output-rate change
- [x] 3.5 Implement the currency income tick (`on_nth_tick`) crediting each builder by their Generator's per-tick output into `storage.currency`

## 4. Builder defenses (spec: builder-defenses)

- [x] 4.1 Define Wall prototypes/tier table (single-entity, per-tier durability) and Turret prototypes/tier table (per-tier damage)
- [x] 4.2 Implement Wall placement (single entity, one HP pool) that blocks the Behemoth at chokes
- [x] 4.3 Implement Wall upgrade-in-place (apply_upgrade or destroy+recreate at same position, carrying health ratio, no gap opened)
- [x] 4.4 Implement per-tier Wall recolor via a `LuaRendering` tinted overlay attached to the entity; destroy+redraw on tier-up
- [x] 4.5 Implement Turret placement that auto-fires on Behemoth-force entities and never on builders
- [x] 4.6 Implement Turret tier upgrade with affordability check and damage increase

## 5. Behemoth combat (spec: behemoth-combat)

- [x] 5.1 Define/choose the Behemoth base entity and its upgradable stats (damage, attack speed, armor, max health)
- [x] 5.2 Implement damage-to-currency via `on_entity_damaged`, awarding only for damage to `builders`-force structures, proportional to `final_damage_amount`
- [x] 5.3 Implement stat-upgrade purchases (damage/attack speed/armor/HP); HP upgrade must not drop current health below its pre-upgrade value
- [x] 5.4 Implement Scanner Sweep ability: chart a target area for the Behemoth force with a cooldown enforced via `game.tick`

## 6. Hiding and vision (spec: hiding-vision)

- [x] 6.1 Configure Behemoth character/unit vision range so scouting is required (no map-wide reveal)
- [x] 6.2 Verify (document as a test case) that builder structures outside live vision stay hidden and appear on approach
- [x] 6.3 Implement the reveal helper used by Scanner Sweep (`force.chart`) and confirm it exposes hidden structures at scan time

## 7. Shop UI (spec: shop-ui)

- [x] 7.1 Build the shop panel in `player.gui.screen`: a `frame` of `sprite-button` tiles filtered by the player's role, with prices
- [x] 7.2 Add a live balance label bound to `storage.currency`, refreshed on change
- [x] 7.3 Implement `on_gui_click` purchase dispatch: affordability check, deduct, apply effect, refresh; reject + notify when unaffordable
- [x] 7.4 Wire shop purchases to economy (generator upgrades), defenses (wall/turret upgrades), and behemoth (stat upgrades, Scanner Sweep)

## 8. Integration and validation

- [ ] 8.1 Confirm all mutable state lives under `storage`; no module-level mutable locals; single permanently-registered `on_nth_tick` branching internally
- [ ] 8.2 Run luacheck and validate `info.json`; fix findings
- [ ] 8.3 Manual end-to-end trace against each spec scenario (dry read-through); note the items needing in-engine verification (fog-of-war reveal, wall block, determinism)
- [ ] 8.4 Write a short README: how to install into Factorio and run on the headless server for playtesting
