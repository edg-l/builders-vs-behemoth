## Why

The core loop needs a real playfield. Builders currently spawn on open nauvis with no defensible terrain and no bounded search space, so "hide and wall a choke" has neither a place to hide nor a choke to wall, and the hunter could chase into infinite terrain. The source mode (Probes vs Zealot 2) is a bounded arena of many single-entry bases scattered around a central hunter hub. This change builds that: a dedicated bounded arena surface with scattered varying-size single-entry pockets, launched as a proper scenario, hunted by a wide vehicle that the chokes can actually stop.

## What Changes

- **Restructure to mod + bundled scenario** so the mode launches from "New Game -> Scenarios" and no longer auto-hijacks freeplay.
- Run the match on a **dedicated bounded arena surface** floored uniformly (`refined-concrete`), free of biters/resources, enclosed by an impassable boundary.
- Generate a **grounded layout**: a central hunter hub, a shared central Builder spawn (Builders roam out and claim), and **many varying-size single-entry pockets, more than players**, on a hub-distance safety gradient with obscure "ninja" nooks — deterministic across peers, regenerated each match.
- Make the **Behemoth a ~2-wide ground vehicle** (tank-based, not spidertron) so the "wall the middle, Builders slip the side gaps" choke works; rework its arming/stats/win-detection accordingly.
- Establish **hiding = physical search + map fog + Scanner Sweep** (true elevation occlusion is not engine-possible; documented and accepted).

## Capabilities

### New Capabilities
- `arena-generation`: the scenario entry, the bounded uniform surface, the central hub, Builder spawn/claim, the scattered varying-size single-entry pockets, deterministic generation + restart, and the search/map-fog hiding model.
- `hunter-vehicle`: the Behemoth as a wide ground vehicle confined to chokes, its armament/upgrade application, and vehicle-based win detection.

### Modified Capabilities
<!-- match-lifecycle and behemoth-combat are affected in implementation (spawn surface, vehicle vs character), but their spec-level intent is unchanged; captured here as the two new capabilities above rather than delta specs, since core-loop-mvp is not yet archived. -->

## Impact

- **New code:** `scenarios/builders-vs-behemoth/control.lua`; a `scripts/main.lua` activation entry; rewritten `scripts/arena.lua`; a tank-based Behemoth prototype.
- **Reworked:** `control.lua` (no auto-start), `scripts/match.lua` (arena surface, central spawn, vehicle Behemoth, restart), `scripts/behemoth.lua` + `prototypes/behemoth.lua` (vehicle), `scripts/vision.lua` (map-fog hiding).
- **Factorio APIs:** `create_surface`, `set_tiles`, `create_entity{name="cliff",…}`/water tiles, `LuaForce.chart`/`unchart_chunk`, vehicle gun/ammo inventories, force ammo/gun-speed modifiers, `on_entity_damaged`.
- **Dependencies:** base game only.
- **Supersedes** the first arena implementation (uniform per-Builder ring pockets), which is replaced.
- **Non-goals:** true elevation/LoS occlusion (impossible); the cosmetic render-overlay fog (deferred); multiple map presets; art. Numbers are placeholders.
