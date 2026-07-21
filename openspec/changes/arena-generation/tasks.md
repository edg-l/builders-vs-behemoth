## 1. Arena module scaffold

- [x] 1.1 Create `scripts/arena.lua` following the module convention (returns table; `on_init` seeds `storage.arena`; no self-registered events); add `storage.arena` to control.lua STORAGE_NAMESPACES and require the module where the others are required
- [x] 1.2 Add an immutable CONFIG with placeholders: `boundary_material` ("cliff" | "water"), `pocket_radius`, `gap_width`, and ring-radius scaling inputs; flag all as to-tune

## 2. Pocket geometry (material-agnostic)

- [x] 2.1 Implement pocket-center computation from a Builder ordinal + count (reuse the same ring math as `match.lua`'s spawn so pocket and spawn coincide); expose a helper `arena.pocket_center(ordinal, count)`
- [x] 2.2 Compute the perimeter positions of a pocket and the contiguous gap span (gap direction a deterministic function of the pocket angle, e.g. facing map center); return boundary positions with the gap omitted
- [x] 2.3 Guard against overlap: if ring spacing < 2*pocket_radius + margin, scale the ring radius up (and `log()` the adjustment) rather than overlapping pockets silently

## 3. Boundary placement (isolated behind one helper)

- [x] 3.1 Implement `place_boundary(surface, positions)` for the cliff material: create cliff segments with correct `cliff_orientation` per position, snapped to the cliff grid, omitting the gap; track created entities in `storage.arena`
- [x] 3.2 Implement the water fallback path in the same helper interface: `set_tiles` water on boundary positions (record original tiles for restart), omitting the gap; selectable via `CONFIG.boundary_material`
- [x] 3.3 Implement `clear_boundary()` : destroy tracked cliff entities and/or revert recorded water tiles to land; clear `storage.arena`

## 4. Integration

- [x] 4.1 Add `arena.generate(builder_indices)` that builds a pocket per Builder ordinal and places boundaries; call it from `match.lua`'s start path BEFORE Builders spawn (so they spawn inside their pocket)
- [x] 4.2 Ensure Builder spawn positions land inside their pocket (adjust spawn to pocket center if needed; keep deterministic)
- [x] 4.3 Call `arena.clear_boundary()` (or regenerate) on match restart so a new match starts from clean terrain

## 5. Verification

- [x] 5.1 Confirm determinism: generation is ordinal-based, no runtime randomness, all state in `storage`
- [x] 5.2 Run `luac5.4 -p` on all touched Lua and `luacheck .` (0/0)
- [x] 5.3 Add an in-engine test-case block (to `docs/verification.md`): pocket has exactly one gap, boundary blocks the Behemoth, gap is wall-able, pockets don't overlap at N builders, restart regenerates cleanly — the cliff-vs-water decision is confirmed here
