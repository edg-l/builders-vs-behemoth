## Why

The core loop is built on hiding and choke-defense, but Builders currently spawn on open terrain with no natural defensible position — nothing channels the Behemoth to a single approach, so "wall the choke" has no choke to wall. The source mode (Probes vs Zealot 2) gives each mouse a base reachable by one ramp. Factorio has no elevation, but scripted terrain can carve the same shape. This change generates, at match start, a single-entry defensible pocket for each Builder.

## What Changes

- Add a scripted arena generator that runs once at match start (before Builders act), carving one enclosed pocket per Builder, each with exactly **one** entry gap (the choke).
- Pocket boundaries are made of **cliffs** (impassable, unbreachable by the Behemoth, the thematic "hills" analog), with a **water-moat** fallback documented if cliff grid-placement proves impractical.
- Integrate with the existing ring spawn: each Builder spawns inside their own pocket, centered on their ring position; the gap faces a consistent direction (e.g. toward the map center where the Behemoth roams).
- Generation is deterministic (index-based, no runtime randomness) so it is identical across multiplayer peers.
- Handle restart: regenerate/clean pockets so a new match starts from known terrain.
- Expose the layout via tunables (pocket radius, gap width, boundary material) with placeholder values.

## Capabilities

### New Capabilities
- `arena-generation`: scripted, deterministic creation of per-Builder single-entry defensible pockets at match start, their integration with spawn placement, and their teardown/regeneration on restart.

### Modified Capabilities
<!-- None — this is additive. match-lifecycle calls the new generator but its own requirements are unchanged. -->

## Impact

- **New code:** a `scripts/arena.lua` module; a call from `match.lua`'s match-start path; wiring consistent with the single-registrar pattern if any event is needed.
- **Factorio APIs:** `LuaSurface.create_entity{name="cliff", cliff_orientation=…}` (grid-snapped, orientation-sensitive) or `LuaSurface.set_tiles` for the water fallback; `LuaSurface.find_entities_filtered`/destroy for cleanup; deterministic index math.
- **Dependencies:** base game only (cliffs and water are base). No new prototypes required.
- **Non-goals:** organic map-gen tuning (cliff noise settings), decorative variety, multiple arena layouts, Behemoth-side terrain. Numbers are placeholders to tune in-engine.
- **Risk:** scripted cliff placement is grid-aligned (4-tile) and orientation-fiddly; the design carries an explicit water-moat fallback if cliffs can't cleanly form a closed single-gap ring at the chosen scale.
