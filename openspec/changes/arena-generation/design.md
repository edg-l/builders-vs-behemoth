## Context

`core-loop-mvp` spawns Builders scattered around a ring on open terrain. The hide + choke-defense loop needs each Builder to have a naturally defensible position with a single approach the Behemoth is forced through. Factorio has no elevation, so we script the terrain. This runs once at match start, is multiplayer-deterministic, and must not depend on organic map generation.

## Goals / Non-Goals

**Goals:**
- One enclosed, single-entry pocket per Builder, generated before play, deterministic across peers.
- Boundary impassable to the Behemoth so the gap is the only approach.
- Clean integration with the existing ring spawn and match restart.

**Non-Goals:**
- Organic cliff-noise map-gen tuning; decorative variety; multiple arena presets; Behemoth-side terrain. Final sizing (tuned in-engine).

## Decisions

### D1: Boundary material — cliffs, with a water-moat fallback
**Chosen:** cliffs. They are impassable, cannot be breached by the Behemoth (no cliff explosives in play), and read as the "hills" the source mode uses. **Fallback (documented, switch via a config flag):** a water moat via `set_tiles`, which is trivial to place and equally impassable, if cliff placement can't cleanly close a ring with one gap at the chosen scale. *Rejected:* indestructible walls — they read as artificial and visually collide with the player's own Walls.

### D2: Scripted, not map-gen-tuned
Generate explicitly with `create_entity`/`set_tiles` at match start rather than tuning `MapGenSettings` noise. Noise cannot guarantee exactly one entry; scripting can. Runs in `arena.lua`, called from `match.lua`'s start path right before Builders spawn.

### D3: Determinism from ordinal, never random
Pocket centers derive from the same sorted Builder ordinal the ring spawn already uses (`angle = (ordinal-1) * 2π/N`, radius from CONFIG). Gap direction is a fixed function of the pocket's angle (e.g. gap faces map center, where the Behemoth roams). No `math.random`. Identical on every peer.

### D4: Cliff placement approach
Cliffs are grid-snapped (4-tile) and orientation-sensitive. The generator will lay a ring of cliff segments around the pocket center at `pocket_radius`, choosing `cliff_orientation` per segment position, and simply **omit** the segments spanning the gap. Because exact cliff geometry is hard to verify without the engine, the module isolates placement behind one helper so the water fallback (D1) can replace it wholesale without touching the pocket/gap logic. If, in-engine, cliffs won't close cleanly, flip the config flag to water.

### D5: Restart handling
On restart, destroy previously generated boundary entities (track them in `storage.arena`, or find cliffs/tiles in the known pocket areas) and regenerate on the next start. Water tiles are reverted to land the same way. Keep all tracking in `storage`.

## Risks / Trade-offs

- [Cliff grid/orientation won't form a clean single-gap ring at small radius] → water fallback behind the D4 helper boundary; the pocket/gap math is material-agnostic.
- [Pockets overlap at high Builder counts on a small ring] → scale ring radius with Builder count (reuse/extend the spawn-ring tunable); validate spacing ≥ 2·pocket_radius + margin, and log/adjust if violated rather than overlapping silently.
- [Terrain generation cost at match start with many Builders] → bounded work (N pockets, fixed perimeter each); acceptable one-time cost; done before the grace period.
- [Determinism] → ordinal-based math only, all state in `storage`, no runtime randomness; matches the existing ring-spawn determinism fix.
- [No in-engine testing here] → isolate placement, keep the fallback, and add the pocket checks to `docs/verification.md`.

## Open Questions

- Exact `pocket_radius`, `gap_width`, ring radius scaling, and whether the gap faces center vs a fixed compass direction — placeholders, tune in-engine.
- Whether to also give the Behemoth a neutral open arena or let it roam freeplay terrain (currently: freeplay terrain; out of scope here).
