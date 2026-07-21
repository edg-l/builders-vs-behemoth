## Context

Supersedes the first arena design (uniform per-Builder ring pockets), which was wrong: it wasn't the bounded, scattered, varied-pocket shape the source mode uses. Research into the real Probes vs Zealot 2 maps (sc2arcade DB + wiki, see the change's research notes) confirms the target: a finite bounded arena; a central hunter hub the hunter radiates from and returns to heal/shop; a shared central spawn Builders flee outward from to claim a pocket of their choice; many single-entry pockets, more than there are players, in a size/safety gradient. This rework also moves the mod to a mod+scenario structure and makes the hunter a wide ground vehicle so the signature choke mechanic works.

## Goals / Non-Goals

**Goals:**
- Mod + bundled scenario entry ("New Game -> Scenarios"), mode logic no longer force-run on arbitrary freeplay.
- A small bounded arena surface with a uniform manufactured floor and no freeplay clutter.
- Many varying-size single-entry pockets scattered around a central hunter hub, more pockets than players, deterministic across peers.
- A ~2-wide ground-vehicle hunter so "wall the middle, Builders slip the side gaps" works.

**Non-Goals:**
- Organic map-gen tuning; multiple arena presets/variants (one layout, size-scaled by player count); decorative art. Numbers are placeholders. (Scripted per-force fog is now IN scope — see D7.)

## Decisions

### D1 (REVISED): Mod + bundled scenario
Ship a mod (needed for prototypes) that bundles a scenario in `scenarios/builders-vs-behemoth/`, whose `control.lua` is a one-line `require` into the mode logic — the base game's own pattern (`base/scenarios/pvp/control.lua` -> `require('__base__/script/pvp/control.lua')`, confirmed in the reference). Move the event-wiring/`on_init` out of the mod's top-level `control.lua` into a module the scenario activates, so a plain freeplay world with the mod enabled does NOT auto-start the mode. Keep an optional console command for dev launch.

### D2: Dedicated arena surface, uniform floor
The scenario's `on_init` creates a dedicated surface (`LuaGameScript.create_surface` with MapGenSettings that suppress resources/enemies/decoratives), then floors the bounded region uniformly with `refined-concrete` via `set_tiles` (tile name verified in the reference). Small and bounded: only the arena region is generated/tiled; everything else stays void/ungenerated. Players play on this surface, not nauvis.

### D3: Bounded playfield
An impassable outer perimeter (cliffs, water fallback) encloses the arena so the hunter's search is finite and nobody leaves. Size scales with player count (small map for few players, larger for many), mirroring the source's size variants.

### D4: Layout (grounded in the source)
- **Central hunter hub:** fixed landmark at arena center; the Behemoth spawns here after the head start, heals near it, and shops here; it radiates outward to hunt.
- **Builder spawn:** all Builders start at/near the central spawn, then run outward to claim a pocket (they are free characters who build wherever — no pre-assignment).
- **Pockets:** more than the player count. Scattered around the hub in a size/safety gradient — small exposed pockets near center, larger contested pockets mid, safest pockets in far corners, a couple of high-value pockets near the hub, plus deliberate off-path "ninja" nooks. Sizes vary. Placement/size are deterministic (seeded from a fixed seed / index math, never unsynced randomness) but visually varied.
- Each pocket is a single-entry choke (D5) sized to the hunter's width (D6).

### D5: Pocket boundary material — cliffs, water fallback
Unchanged from the prior design: cliffs (square box, gap omitted, orientation constants from base PvP `create_moat_for_force`), with a one-flag water-moat fallback. Isolated behind one placement helper.

### D6 (NEW): Hunter is a ~2-wide ground vehicle
The Behemoth becomes a controllable **tank-based** vehicle (clone `tank`), NOT a spidertron (spidertrons cross cliffs/water and would bypass every choke). Chokes are a central wall plus ~1-tile side gaps: Builders (small characters) pass, the ~2-wide tank cannot. Consequences to rework in `behemoth.lua`/`prototypes/behemoth.lua`:
- **Arming:** insert weapon/ammo into the vehicle's gun/ammo inventories (not `character_guns`/`character_ammo`); keep the custom ammo category so force modifiers stay scoped.
- **Stats:** damage/attack-speed via `set_ammo_damage_modifier`/`set_gun_speed_modifier` on the ammo category (works for vehicles). Armor via scripted mitigation on the vehicle entity (as today). Max-health: `character_health_bonus` does NOT apply to vehicles — use a scripted approach (script the entity's health cap via tiered vehicle prototypes, or an additive damage-absorb pool). Flagged as the trickiest bit, verify in-engine.
- **Win detection:** detect the Behemoth *vehicle* being destroyed (the player is ejected, not killed), not character death. Track the vehicle entity in `storage`.

### D7 (REVISED — accurate engine model): Hiding = physical search + map fog; true in-game occlusion is not natively possible
Factorio has only MAP fog (chart-based, per-force, drives the minimap + "explored" state, moddable via `chart`/`unchart_chunk`). The main game VIEW has no moddable fog: a force renders live entities within its radial vision (character/vehicle/radar) with NO elevation and NO line-of-sight occlusion, and there is NO API to hide a live entity in the main view from a specific force. So PvZ2's "adjacent-but-below can't see up" CANNOT be reproduced natively — a hunter within vision radius of a pocket will see it on screen, and `unchart_chunk` only re-fogs the MAP, not the viewport. (This corrects an earlier version of this doc that treated scripted chart-fog as true occlusion.)

Chosen approach:
- **Baseline (coherent, shipped):** hiding = physical search + map fog. Keep the tank's vision radius modest so it must approach/enter to see a pocket (radial vision already does most of this); use map-fog so the minimap doesn't give away base locations. Scanner Sweep (`force.chart`) is the hunter's peek tool.
- **Optional (deferred hack):** `LuaRendering.draw_rectangle`/`draw_sprite` accept a `forces` filter, so we could paint an opaque per-force overlay over pocket interiors for the hunter only, lifted when the tank enters — a DIY in-game fog. Caveat: cosmetic only (doesn't change what the tank can target/interact with, so it can read incoherently). Only if the visual matters; not a promise.
- NOT attempting true elevation/LoS occlusion — the engine doesn't model it and the API doesn't expose it.

## Risks / Trade-offs

- [Vehicle max-health upgrade has no clean force modifier] -> use tiered vehicle prototypes or a scripted absorb pool; verify in-engine; simplest MVP may cap HP upgrades or use overheal.
- [Tank drives over water? no; over cliffs? no — but confirm it can't climb the chosen boundary] -> pick the boundary material the tank genuinely cannot cross; water is a safe guarantee, cliffs need confirming for tanks.
- [Cliff square geometry unverified in-engine] -> water fallback (unchanged).
- [Pocket overlap / fitting more-than-N pockets in a small bounded area] -> deterministic layout with spacing guard; scale arena size with player count; log adjustments.
- [Scenario/mod restructure breaks existing event wiring] -> mirror base game exactly; keep all mode modules unchanged behind the new entry; re-verify luacheck.
- [Determinism] -> seeded/index-based layout, all state in storage, no unsynced randomness.
- [Fog re-unchart fights the hunter's own charting; per-tick cost] -> re-`unchart_chunk` only the pocket-interior chunks NOT currently occupied by the hunter, on a short `on_nth_tick`; bounded to pocket chunks, not the whole map. Chunk-align pockets so the hide boundary is clean. Watch for reveal/hide pop-in at the choke; tune the reveal trigger radius.
- [Fog is per-force] -> keep pockets hidden only for the hunter force; Builders' force charts normally. Cannot hide from one Builder but not another (acceptable; all Builders are one team).
- [No in-engine testing] -> keep fallbacks, add every new behavior (esp. the fog occlusion feel) to docs/verification.md.

## Open Questions

- Exact arena size per player count, pocket count/size distribution, hub size, choke widths, tank stats — placeholders, tune in-engine.
- Whether the Builder central spawn is a small safe hub or exposed (source: exposed, they must flee) — default exposed.
- Vehicle HP-upgrade mechanism final choice — decide during implementation against the reference.
