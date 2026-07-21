# Verification: spec-to-code trace (core-loop-mvp, task 8.3)

This is a manual, static (dry read-through) trace of every `#### Scenario:` in
`openspec/changes/core-loop-mvp/specs/*/spec.md` against the actual
implemented code. There is no Factorio install on the dev machine (see
design.md's "No local runtime testing" risk), so this can only confirm that a
plausible, complete code path exists for each scenario — it does NOT
substitute for playtesting. Anything whose real behavior depends on the live
engine (physics, targeting AI, fog-of-war timing, GUI rendering, multiplayer
determinism) is called out explicitly in "Needs in-engine verification"
below and must be re-checked on the actual game/headless server before
calling the MVP done.

Verdict legend:
- **OK** — a corresponding code path exists and is a plausible, complete
  implementation of the scenario.
- **needs-in-engine-check** — the scenario's outcome is fundamentally
  governed by native Factorio engine behavior (collision, unit targeting,
  fog of war, rendering) rather than custom logic this repo can statically
  confirm; code path is present/consistent with design but cannot be proven
  correct by reading code alone.
- **gap** — no corresponding code exists for the scenario. (None found; see
  summary.)

Total: 38 scenarios across 6 specs. **30 OK, 8 needs-in-engine-check, 0 gaps.**

## match-lifecycle

| Scenario | Code location | Verdict |
|---|---|---|
| Player picks Builder | `scripts/match.lua:111` `set_role_vote` (records the vote); actual force assignment happens at match start in `M.resolve_behemoth` (`scripts/match.lua:280-316`), which moves every non-Behemoth connected player onto `game.forces.builders`. Deferred-but-eventually-correct: the vote itself only records intent; the force move happens once, at `start_match()`. | OK (see note) |
| Exactly one Behemoth is chosen | `scripts/match.lua:280-302` `M.resolve_behemoth`: collects `role_votes == "behemoth"` volunteers, picks one via `math.random(#volunteers)`, assigns everyone else to `builders`. | OK |
| No Behemoth volunteer | `scripts/match.lua:298-301`: `#volunteers == 0` branch picks `connected[math.random(#connected)]`. | OK |
| Forces are mutually hostile | `scripts/match.lua:270-278` `M.setup_forces`: creates `builders`/`behemoth` forces, calls `set_cease_fire` in both directions (D2). | OK |
| Builders do not fight each other | No custom targeting code; relies on all Builder players sharing the single `builders` force (native Factorio same-force non-aggression for units/turrets). No override found anywhere in `prototypes/turrets.lua` or `scripts/defenses.lua`. | needs-in-engine-check |
| Behemoth head-start delay | `scripts/match.lua:226-249` `start_match`: spawns builders immediately (`spawn_builder` loop), holds Behemoth as spectator (`hold_behemoth_waiting`), sets `behemoth_spawn_tick = game.tick + CONFIG.behemoth_head_start_ticks`; `M.on_countdown_tick` (`:355-365`, wired from `control.lua`'s `on_nth_tick(30)`) updates the countdown label and calls `spawn_behemoth_now()` once the tick elapses. | OK |
| Behemoth victory | `scripts/match.lua:369-393` `M.on_entity_died`: builder's character dies -> removed from `builder_player_indices`; when the set is empty, `M.end_match("behemoth")`. | OK |
| Builders victory | Same handler: Behemoth's character dies (`player_index == storage.match.behemoth_player_index`) -> `M.end_match("builders")`. | OK |
| Match teardown | `scripts/match.lua:395-406` `M.end_match`: `game.print` result message, `show_end_gui` for all connected players; GUI's restart button (`END_RESTART_BUTTON_NAME`) dispatches to `restart_match()` (`:207-221`), which resets `storage.match` and re-shows the role-selection GUI. | OK |

## builder-economy

| Scenario | Code location | Verdict |
|---|---|---|
| Placing the first Generator | `scripts/economy.lua:56-80` `M.on_built_entity`: matches `CONFIG.generator_entity_name`, requires `event.player_index`, rejects if `storage.generators[player_index]` already set, else records `{entity, tier=1, unit_number}`. Force is the placing player's force (native `on_built_entity` behavior — the player is already on `builders` post-match-start). | OK |
| Only one Generator per Builder | `scripts/economy.lua:68-78`: on a second placement, `player.insert(...)` refunds the item, `player.print` notifies, `entity.destroy()`. | OK |
| Salvage refund | `scripts/economy.lua:87-96` `M.on_player_mined_entity`: clears `storage.generators[player_index]` when the mined entity matches the tracked record; base game returns the item to inventory natively (comment at `:82-85`). | OK |
| Upgrading a tier | `scripts/economy.lua:119-136` `M.upgrade_generator`, invoked from `scripts/shop.lua:219-224`: checks next tier exists, checks balance, deducts, bumps `record.tier`. | OK |
| Insufficient funds | Same function, `:129-131`: returns `false, "insufficient-funds"` before any mutation; `shop.lua`'s `finish_purchase`/`notify_reason` prints, applies nothing. | OK |
| Income accrues over time | `scripts/economy.lua:140-147` `M.on_income_tick`, wired from `control.lua`'s `on_nth_tick(60)`: iterates `storage.generators`, adds `tier_stats.income_per_interval` via `M.add_currency`. | OK |
| No Generator, no income | Same loop only iterates keys present in `storage.generators`; a player with no record is never touched, balance unchanged. | OK |

## builder-defenses

| Scenario | Code location | Verdict |
|---|---|---|
| Wall blocks the Behemoth | `prototypes/walls.lua:30-34`: each tier clones `data.raw["wall"]["stone-wall"]` (inherits its collision box/mask), only `max_health`/`minable`/`name` are overridden — collision is untouched. Whether this actually blocks a character physically is native engine collision, not scripted. | needs-in-engine-check |
| Wall has a single health pool | One entity per Wall (`prototypes/walls.lua` — a genuine prototype, not a multi-tile group); `storage.walls[unit_number]` tracks exactly one `LuaEntity`/health per Wall (`scripts/defenses.lua:99`). | OK |
| Upgrade in place | `scripts/defenses.lua:146-193` `M.upgrade_wall`: captures `health_ratio`, destroys the old entity and creates the new tier's at the same `position`/`direction`/`force` synchronously (no tick elapses in between, so no gap opens), applies `new_entity.health = new_entity.max_health * health_ratio`. | OK |
| Per-tier visual | `scripts/defenses.lua:197-216` `M.redraw_wall_overlay`: destroys any existing overlay, draws a new `rendering.draw_sprite` tinted per `CONFIG.wall_tiers[tier].tint`, targeted at the entity. Whether the overlay renders correctly (layer, scale, alignment against the base wall sprite) is a rendering-only concern flagged as a risk in design.md ("Recolor overlay render-layer/scale mismatch"). | needs-in-engine-check |
| Turret engages the Behemoth | No custom targeting code in `scripts/defenses.lua`; relies entirely on the cloned `ammo-turret` ("gun-turret") prototype's native auto-target-hostile-force behavior (`prototypes/turrets.lua:40-43`) plus `builders`/`behemoth` cease-fire (match.lua). | needs-in-engine-check |
| Turret ignores Builders | Same native mechanism: the Turret's force is the placing Builder's force (`builders`), and ammo-turrets do not target same-force entities by default; no override present. | needs-in-engine-check |
| Turret upgrade | `scripts/defenses.lua:226-251` `M.upgrade_turret`: checks tier/balance, deducts, bumps `record.tier`, clears the ammo inventory and refills with the new tier's ammo item (`refill_turret_ammo`, `:59-75`). Damage increase is enforced by the new ammo's `target_effects` (`prototypes/turrets.lua:61-88`), not by this function directly. | OK (ammo-turret "instant" trigger schema itself listed under needs-in-engine-check below) |

## behemoth-combat

| Scenario | Code location | Verdict |
|---|---|---|
| Damaging a structure pays out | `scripts/behemoth.lua:191-203` `M.on_entity_damaged`: `entity.force.name == "builders"` and `CONFIG.builder_structure_names[entity.name]` -> `economy.add_currency(behemoth_player_index, math.floor(event.final_damage_amount * CONFIG.income_rate))`. | OK |
| Damage to non-structures does not pay | Same handler: the structure-name whitelist (`CONFIG.builder_structure_names`, `:52-58`) excludes characters/terrain/neutral entities by construction; only the Behemoth's own character hitting the "not force==builders" branch triggers armor mitigation (`:205-212`), never a currency award. | OK |
| Purchasing a stat upgrade | `scripts/behemoth.lua:223-246` `M.upgrade_stat`: checks caller is the Behemoth, checks next tier/balance, deducts, sets `storage.behemoth.stat_tier[stat_name]`, calls `apply_stat_tier` (`:104-124`) which applies the tier via `LuaForce.set_ammo_damage_modifier` / `set_gun_speed_modifier` / a scripted armor-mitigation counter / `character_health_bonus`. | OK |
| Health upgrade preserves current health ratio | `apply_stat_tier`'s `max_health` branch (`:112-123`): captures `pre_health` before setting `force.character_health_bonus`, then restores `character.health = pre_health` if the change would otherwise have dropped it. | OK |
| Revealing an area | `scripts/behemoth.lua:260-277` `M.scanner_sweep` -> `scripts/vision.lua:89-100` `M.reveal_area` -> `force.chart(surface, area)` on a `2*radius` square centered on the target position. | OK |
| Cooldown enforced | `scripts/behemoth.lua:264-266`: rejects with `"on-cooldown"` while `game.tick < storage.behemoth.scanner_sweep_ready_tick`; on success sets `scanner_sweep_ready_tick = game.tick + CONFIG.scanner_sweep_cooldown_ticks` (`:275`). Tick-based, deterministic. | OK |

## hiding-vision

| Scenario | Code location | Verdict |
|---|---|---|
| Base built out of sight stays hidden | No custom "hidden" state anywhere (grep confirms no `storage.hidden`/visibility bookkeeping exists); relies entirely on Factorio's native fog-of-war per design D7. Documented as an explicit in-engine test case in `scripts/vision.lua:102-149` (Scenario A). | needs-in-engine-check |
| Walking into vision reveals | Same native mechanism; documented as Scenario B in `scripts/vision.lua:123-131`. `scripts/vision.lua:64-71` `M.configure_behemoth_vision` is an intentional no-op (Factorio 2.0 exposes no moddable character vision radius at either stage — documented constraint, not a skipped task) relying on default character vision. | needs-in-engine-check |
| Concealment is distance/observation based | Verifiable by absence: no elevation/line-of-sight code exists anywhere in the repo (grep for "elevation"/"line_of_sight"/"los" returns nothing); the only reveal mechanism is `force.chart` (distance/observation-based charting). | OK |
| Scan exposes a hidden base | `scripts/behemoth.lua:260-277` -> `scripts/vision.lua:89-100` `reveal_area` (`force.chart`), documented as Scenario C in `scripts/vision.lua:133-148`. The chart call itself is a verified API (per `openspec/config.yaml`'s "Scanner Sweep = LuaForce.chart(surface, area)"), but whether the revealed structures actually render live/for the expected duration before fog reclaims the area is native fog-of-war behavior. | needs-in-engine-check |

## shop-ui

| Scenario | Code location | Verdict |
|---|---|---|
| Opening the shop | `scripts/shop.lua:340-347` `M.toggle` -> `M.open` (`:288-329`): builds the `player.gui.screen` frame with balance label + item tiles + close button. | OK |
| Role-appropriate contents | `scripts/shop.lua:178-186` `get_role` (reads `storage.match.behemoth_player_index`/`builder_player_indices`, read-only); `M.open` (`:303-322`) selects `CONFIG.builder_items` or `CONFIG.behemoth_items` accordingly, or a "no role yet" label otherwise. | OK |
| Balance updates after income | `scripts/shop.lua:351-361` `M.refresh_balance` reads `economy.get_currency`; called on open, after every purchase (`finish_purchase`, `:197-203`), and periodically via `M.on_balance_tick` (`:368-375`, wired in `control.lua`'s `on_nth_tick(60)` immediately after `economy.on_income_tick`). | OK |
| Affordable purchase | `scripts/shop.lua:219-256` `handle_builder_purchase`/`handle_behemoth_purchase` call the owning module's `upgrade_*`/`scanner_sweep` function, which internally deducts+applies only on success; `finish_purchase` then calls `refresh_balance`. | OK |
| Unaffordable purchase | Same dispatch: the owning module returns `false, "insufficient-funds"` without mutating anything; `finish_purchase` -> `notify_reason` prints, does not refresh (nothing changed). | OK |

## Needs in-engine verification (cross-cutting, not fully covered by the table above)

These cannot be confirmed by reading code; they must be checked on the real
game/headless server before the MVP is considered validated:

1. **Wall physically blocking the Behemoth** (builder-defenses "Wall blocks
   the Behemoth") — collision is inherited from `stone-wall` and never
   overridden, but actual pathing/collision behavior against a player
   character is an engine-runtime fact.
2. **Turret targeting via force hostility** (builder-defenses "Turret
   engages the Behemoth" / "Turret ignores Builders") — no scripted
   targeting exists; this depends entirely on native ammo-turret AI
   respecting force relations as expected for a cloned `gun-turret`.
3. **Ammo-turret "instant" trigger nesting** (builder-defenses "Turret
   upgrade"; behemoth-combat weapon in `prototypes/behemoth.lua`) — the
   `ammo_type.action = { type = "direct", action_delivery = { type =
   "instant", target_effects = {...} } }` schema was authored from the
   Factorio 2.0 prototype docs, not tested against the real data-stage
   loader; confirm it actually loads and deals the configured damage.
4. **`LuaForce` modifier API names** (behemoth-combat stat upgrades) —
   `set_ammo_damage_modifier`, `set_gun_speed_modifier`,
   `character_health_bonus` are used per `openspec/config.yaml`'s verified
   mapping and Factorio's own combat-tech mechanism, but the exact
   ammo-category/gun-speed scoping (`CONFIG.weapon_ammo_category`) has not
   been exercised in a running game.
5. **Fog-of-war reveal/re-hide timing** (hiding-vision, all three
   native-mechanism scenarios) — chunk charted-vs-live-vision semantics,
   confirmed only by design reading and Factorio's documented model, not by
   a running match. See `scripts/vision.lua`'s in-file Scenario A/B/C test
   procedures — run those manually.
6. **Wall/Turret recolor overlay rendering** (builder-defenses "Per-tier
   visual") — `LuaRenderObject` layer/scale/position relative to the base
   entity sprite; flagged as a risk in design.md.
7. **GUI rendering/layout** (match-lifecycle role-selection/countdown/
   end-of-match frames; shop-ui panel) — retained-mode GUI element
   creation is code-verified, but actual on-screen layout, multi-monitor/
   resolution behavior, and click-target hitboxes need a real client.
8. **Multiplayer determinism/desync** (all of the above, in aggregate) —
   task 8.1's static audit found no determinism violations (see below), but
   the only real confirmation of lockstep-safe behavior is a multiplayer
   session on the headless server across several minutes of play.
9. **`entity.unit_number` non-nil assumption** — `storage.walls`/
   `storage.turrets`/`economy`'s generator record are keyed directly by
   `entity.unit_number` (`scripts/defenses.lua:99,109`; `scripts/economy.lua:79`)
   with no nil guard. Walls/Turrets/Generators are all destructible,
   minable entities, which should always receive a `unit_number` per the
   `LuaEntity.unit_number` API docs, but this has not been confirmed against
   a running Factorio 2.0 instance.

## Gaps found

None. Every scenario in every spec under
`openspec/changes/core-loop-mvp/specs/*/spec.md` has a corresponding,
plausible code path (see the tables above).

## Determinism audit (task 8.1)

Static audit result: **clean, no violations found.** Evidence:

- **All mutable gameplay state lives under `storage`.** Every module-level
  `local` in `scripts/*.lua` is one of: the module's own function table
  (`local M = {}`), a `require`d module reference, an immutable `CONFIG`
  tunables table (never assigned into after its literal definition — checked
  via `grep -n "CONFIG\.[a-zA-Z_]* *=" scripts/*.lua prototypes/*.lua`,
  zero matches), a derived read-only lookup table built once from `CONFIG` at
  module load (`scripts/shop.lua`'s `BUILDER_ITEM_BY_NAME`/
  `BEHEMOTH_ITEM_BY_NAME`, populated once immediately after `CONFIG`'s
  definition and never written to again outside that loop), a GUI
  element-name string constant, or a private helper function. None of these
  are runtime counters/flags that get mutated tick-to-tick outside
  `storage` — all per-match state (`role_votes`, `phase`, `behemoth_player_index`,
  `stat_tier`, `armor_mitigation`, `scanner_sweep_ready_tick`,
  `generators`/`walls`/`turrets`/`currency`/`shop` records) lives in
  `storage.*`, seeded from `control.lua`'s `STORAGE_NAMESPACES` list and each
  module's own `on_init`.
- **Single permanently-registered `on_nth_tick`/`on_event` set.** `grep -rn
  "script\.on_event\|script\.on_nth_tick\|script\.on_init\|script\.on_load"`
  across the whole repo shows every one of these calls lives in
  `control.lua` only; no `scripts/*.lua` module calls `script.on_event` or
  `script.on_nth_tick` itself. `control.lua` registers exactly two
  `on_nth_tick` cadences (60 and 30) and a fixed set of `on_event` handlers,
  all unconditionally at file scope; each handler branches internally on
  `storage`-held phase/role state (e.g. `match.on_countdown_tick` checks
  `storage.match.phase ~= "starting"` and returns early) rather than being
  added/removed at runtime.
- **Time comes from `game.tick` everywhere.** `grep -rn
  "os\.\(time\|clock\|date\)"` across all `*.lua` returns zero matches.
  Every cooldown/countdown/delay (`behemoth_spawn_tick`,
  `scanner_sweep_ready_tick`) is computed from `game.tick`.
- **Randomness.** The only random call site (`scripts/match.lua:297,301`,
  Behemoth resolution) uses `math.random`, matching the determinism rule (no
  `os`-seeded/non-deterministic sources).
- **No accidental globals.** `grep`-based scan for bare `name = value`
  assignments at statement start found only field assignments on
  already-`local`-declared prototype tables in `prototypes/*.lua`
  (`generator_entity.name = ...`, etc.), not top-level global leaks;
  confirmed independently by `luacheck` (see task 8.2 below), which reports
  zero warnings for undefined/accidental globals.
- **`game`/`storage` access boundaries.** Every module's `on_load()` is a
  no-op comment ("No `game` access here"); `game` is only touched inside
  event-handler bodies, never at file scope.

No fixes were required for 8.1; the codebase was already clean against
these rules going into this phase.

## Static validation (task 8.2)

- `python3 -m json.tool info.json` — **valid JSON.**
- `luacheck .` — luacheck WAS successfully installed for this pass
  (`sudo apt-get install -y luarocks`, then
  `TMPDIR=~/.cache/tmp luarocks --local install luacheck`) and run across
  every `.lua` file in the repo. Initial run: **0 errors, 63 warnings**
  across 3 categories, all fixed:
  1. `setting read-only field ... of global storage` / `game` (57
     warnings) — false positive from `.luacheckrc` declaring `storage`/
     `game` as `read_globals`; both are legitimately written through at
     runtime (that's the entire point of `storage`, and `game.forces.*`
     modifier fields). Fix: moved `storage`/`game` from `read_globals` to
     `globals` in `.luacheckrc`.
  2. `accessing undefined field deepcopy of global table` (6 warnings,
     `prototypes/*.lua`) — `table.deepcopy` is a Factorio data-stage stdlib
     extension not part of vanilla Lua's `table` library. Fix: added
     `table = { fields = { "deepcopy" } }` to `.luacheckrc`'s
     `read_globals`.
  3. `unused argument event` (5 warnings) — the periodic-tick module API
     convention (`on_income_tick(event)`, `on_ammo_tick(event)`,
     `on_equip_tick(event)`, `on_countdown_tick(event)`,
     `on_balance_tick(event)`) requires each handler to accept `event` to
     match the callback signature `control.lua` calls it with, even when
     the handler body doesn't read it. Fix: renamed the parameter to
     `_event` at each of the 5 call sites (leading underscore is luacheck's
     convention for "intentionally unused"), which reads clearly as "this
     exists for the ABI, not because we use it" without disabling the
     unused-argument check project-wide.
  Re-run after fixes: **0 warnings / 0 errors in 12 files.**
- `luac5.4 -p <file>` — run regardless, per task instructions, on every
  `.lua` file in the repo (`control.lua`, `data.lua`, `prototypes/*.lua`,
  `scripts/*.lua` — 12 files total): **all 12 parse cleanly**, no syntax
  errors.

## Files touched by this phase

- `.luacheckrc` — `storage`/`game` moved to mutable `globals`; added
  `table.deepcopy` field declaration.
- `scripts/behemoth.lua`, `scripts/economy.lua`, `scripts/defenses.lua`,
  `scripts/shop.lua`, `scripts/match.lua` — renamed one unused tick-handler
  parameter each (`event` -> `_event`) to silence a real luacheck finding.
- `docs/verification.md` — this file (new).
- `README.md` — expanded per task 8.4.
