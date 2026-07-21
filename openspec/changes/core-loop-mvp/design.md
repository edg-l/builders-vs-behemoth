## Context

Greenfield Factorio 2.0 mod. The proposal defines an asymmetric 1-hunter-vs-many-builders match; the six capability specs define the required behavior. This document fixes the technical approach so implementation is unambiguous.

Hard constraints (from the Factorio platform and the dev environment):
- Multiplayer lockstep determinism: all mutable state in `storage`, time from `game.tick`, randomness only via `math.random` / `LuaRandomGenerator`, event handlers registered permanently and branched inside.
- Custom prototypes (Generator/Wall/Turret tiers, the Behemoth) require a data stage, so this ships as a **mod**. A thin bundled scenario may select the mod's map later; not required for MVP.
- No Factorio installed on the dev machine: authoring + static checks only (luacheck, JSON validation). Runtime testing happens later on the game or headless server.

## Goals / Non-Goals

**Goals:**
- A runnable mod skeleton (`info.json`, data stage, `control.lua` + `scripts/`) implementing all six MVP capabilities end to end.
- Prove the core loop is fun: hide, build economy, defend chokes, hunter farms damage and snowballs, someone wins.
- A single-file-per-concern control layout that's easy to extend with later changes (respawn roles, maps, deeper trees).

**Non-Goals:**
- Hunter/Spirit respawn roles, multiple maps, deep tier trees, achievements/stats/leaderboards, custom art, AI Behemoth (all deferred).
- Final balance. Numbers are placeholders.

## Decisions

### D1: Ship as a mod, not scenario-only
Custom entity prototypes and tier stats live in the data stage, which scenarios alone don't run. **Chosen:** a mod with `data.lua` prototypes + `control.lua` runtime. *Alternative rejected:* scenario-only reusing base entities — too limiting for tiered custom stats and recoloring.

### D2: Two forces, mutual hostility set both directions
Create `builders` and `behemoth` forces in `on_init`/match-start; `set_cease_fire(other, false)` on **both** (relations are unidirectional). All builder players share the `builders` force so they're auto-allied. *Rationale:* forces are Factorio's native team + diplomacy + shared-vision primitive.

### D3: Currency as plain `storage` counters
`storage.currency` keyed by `player_index` (per-player economy, matching the source mode where each builder banks independently). Behemoth has its own entry. *Alternative rejected:* base-game `coin` item / market entity — heavier and unnecessary for a numeric balance.

### D4: Behemoth income via `on_entity_damaged`
Handler filters `event.entity.force.name == "builders"` and awards `floor(event.final_damage_amount * rate)` to the Behemoth. *Rationale:* `final_damage_amount` is the post-resistance damage actually dealt, matching the "1 dmg = 1 currency" intent. Builder income via `on_nth_tick` iterating active generators.

### D5: Wall = one entity per choke, tier via replace-in-place
Each Wall is a single entity (single HP pool, per spec). Upgrade = `apply_upgrade`/`next_upgrade` where possible, else scripted destroy+`create_entity` at the same position carrying over the health ratio. *Alternative rejected:* connected-tile HP pooling — fragile connected-component bookkeeping for no gameplay gain.

### D6: Per-tier wall recolor via LuaRendering overlay
`wall` prototypes don't support runtime `entity.color`. **Chosen:** draw a tinted `LuaRenderObject` (`rendering.draw_sprite{ target = {entity=wall}, tint = tierColor }`), destroy + redraw on tier-up. *Alternative kept in reserve:* build walls as `simple-entity-with-owner` (supports `entity.color`) if native wall connection graphics aren't needed.

### D7: Hiding = native fog of war, reveal = charting
No extra "hide" system: builder structures outside the Behemoth's live vision are already invisible, and new structures in charted-but-unwatched chunks stay hidden until re-observed. Scanner Sweep = `force.chart(surface, area)` around a target for a timed reveal. Behemoth character vision range tuned small enough that scouting matters. *Rationale:* the platform already implements exactly the desired concealment; fighting it would be wasted effort.

### D8: Shop GUI in `player.gui.screen`
One reusable builder module renders a `frame` of `sprite-button` tiles filtered by role, with a balance label; `on_gui_click` dispatches on `element.name`, checks affordability against `storage.currency`, deducts, applies effect, refreshes. *Rationale:* retained-mode GUI is the standard Factorio approach; one dispatcher keeps purchase logic in one place.

### D9: Control-layer file layout
`control.lua` wires events to modules under `scripts/`: `match.lua` (lifecycle/forces/win-lose), `economy.lua` (currency + income tick), `defenses.lua` (walls/turrets + upgrades + recolor), `behemoth.lua` (damage income, stat upgrades, Scanner Sweep), `vision.lua` (reveal helpers), `shop.lua` (GUI). All state namespaced under `storage`.

## Risks / Trade-offs

- [Determinism desync from careless state] → Keep every mutable value in `storage`; no module-level mutable locals; single permanently-registered `on_nth_tick` that branches internally.
- [Behemoth collision can't reproduce SC2's "wide unit slips through 1-tile gap" trick] → Accept: rely on Walls fully blocking chokes; treat gap-squeeze as out of scope for MVP.
- [Fog-of-war reveal edge cases (charting shows stale state)] → Verify in-engine during first playtest; Scanner Sweep re-charts to force refresh; document as a test case.
- [Recolor overlay render-layer/scale mismatch on upgraded walls] → Centralize overlay draw in `defenses.lua`; one place to fix offsets/layers.
- [No local runtime testing] → Lean on luacheck + JSON validation now; first real validation is on the game/headless server. Keep functions small and side-effect-isolated to ease that later pass.
- [Per-player vs shared-team economy ambiguity] → MVP uses per-player banks (`player_index`); revisit if team-bank play-tests better.

## Open Questions

- Behemoth base entity: reskinned behemoth biter vs tank vs spidertron — decide at prototype time based on desired feel and controllability.
- Exact head-start delay, income rates, tier counts/costs, vision radius — all placeholders to set during first tuning pass.
- Does MVP need a bundled map/scenario, or is freeplay-surface setup in `on_init` enough to playtest? Lean freeplay for now.
