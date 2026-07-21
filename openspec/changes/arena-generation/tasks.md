## 1. Mod + scenario restructure

- [ ] 1.1 Move the mode's event-wiring/on_init out of the top-level `control.lua` into a module (e.g. `scripts/main.lua`) that exposes a single activation entry; the mod's `control.lua` no longer auto-starts the mode
- [ ] 1.2 Add `scenarios/builders-vs-behemoth/control.lua` as a one-line `require` into the activation entry (mirroring base `scenarios/pvp/control.lua`)
- [ ] 1.3 Verify the mode does NOT run on a plain freeplay world with the mod enabled; add a dev-only console command to launch it manually if desired

## 2. Dedicated arena surface

- [ ] 2.1 On scenario init, create a dedicated surface with MapGenSettings suppressing enemies, resources, cliffs (we place our own), and decoratives
- [ ] 2.2 Floor the bounded arena region uniformly with `refined-concrete` via `set_tiles`; leave everything outside ungenerated/void
- [ ] 2.3 Enclose the region with an impassable boundary (cliffs; water fallback) so the playfield is finite; size the region from player count
- [ ] 2.4 Move all player spawning onto this surface (replace the nauvis assumption in match.lua)

## 3. Grounded layout generation (rewrite arena.lua)

- [ ] 3.1 Central hunter hub: a fixed hub area at arena center (Behemoth spawn + heal + shop anchor)
- [ ] 3.2 Central Builder spawn: Builders spawn at a shared central point and are free to roam/claim (remove the per-builder ring assignment)
- [ ] 3.3 Deterministic scattered pockets, MORE than the player count, chunk-aligned, with varying sizes on a hub-distance safety gradient (exposed near center, larger/safer toward edges, plus obscure off-path nooks); seed from a fixed value, no unsynced randomness
- [ ] 3.4 Each pocket: single-entry choke sized to the vehicle width (central wall + gap the tank can't pass); reuse the cliff/water boundary helper
- [ ] 3.5 Overlap/fit guard: ensure pockets don't overlap and fit the bounded region; scale region size and `log()` adjustments
- [ ] 3.6 Regenerate cleanly on match restart

## 4. Wide tank Behemoth (rework behemoth + prototype)

- [ ] 4.1 Define the Behemoth vehicle prototype (clone `tank`, ~2 wide, custom weapon on the existing `bvb-behemoth-weapon` ammo category); NOT a spidertron
- [ ] 4.2 Spawn/enter: seat the Behemoth player in the vehicle at the hub after the grace period (replace character spawn for the Behemoth)
- [ ] 4.3 Arming: insert weapon/ammo into the vehicle's gun/ammo inventories; keep it idempotent and armed immediately on spawn
- [ ] 4.4 Stats: damage/attack-speed via force ammo/gun-speed modifiers (unchanged); armor via scripted mitigation on the vehicle; max-health via a vehicle-appropriate mechanism (tiered prototype or scripted absorb pool) — pick one, document it
- [ ] 4.5 Win detection: track the Behemoth vehicle entity and end the match (Builders win) when it is destroyed; handle the driver being ejected
- [ ] 4.6 Damage-to-currency: confirm the vehicle's fire still credits currency via on_entity_damaged (cause = the vehicle)

## 5. Hiding (baseline)

- [ ] 5.1 Give the Behemoth vehicle a modest vision radius so it must approach/enter pockets to see them
- [ ] 5.2 Keep Builder base locations off the Behemoth's minimap until observed (map-fog management); confirm Scanner Sweep still reveals via `force.chart`
- [ ] 5.3 Do NOT implement true in-game occlusion (accepted limitation); leave the per-force render-overlay hack unimplemented, noted as future

## 6. Integration and verification

- [ ] 6.1 Reconcile match.lua: central spawn, arena.generate before spawn, vehicle-based Behemoth, restart clears arena + vehicle + fog state; keep all prior audit fixes intact
- [ ] 6.2 Determinism: index/seed-based layout, all state in `storage`, no unsynced randomness, single-registrar events
- [ ] 6.3 `luac5.4 -p` on all Lua + `luacheck .` (0/0); `openspec validate arena-generation`
- [ ] 6.4 Update `docs/verification.md` with the in-engine checklist: scenario launches, uniform bounded surface, hub, more-pockets-than-players, single-entry chokes block the tank, tank can't slip side gaps, hiding-by-search, restart clean, cliff-vs-water decision
