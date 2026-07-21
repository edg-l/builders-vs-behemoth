## 0. In-engine spikes (do first; gate the rest)

- [ ] 0.1 SPIKE: place a tank and drive it into a cliff, a water tile, and a `stone-wall` clone — confirm all three block it. This underwrites the whole redesign (D15). If it fails, stop and rethink before investing.
- [ ] 0.2 SPIKE: smallest repro of the bounded surface (rocket-rush `out-of-map` autoplace default + `request_to_generate_chunks` + `force_generate_chunk_requests` + `set_tiles` a small concrete square). Confirm the void boundary is impassable.

## 1. Mod + scenario restructure

- [x] 1.1 Move the mode's event-wiring/on_init out of top-level `control.lua` into a `scripts/main.lua` activation entry; `control.lua` no longer auto-starts the mode
- [x] 1.2 Add `scenarios/builders-vs-behemoth/control.lua` as a one-line `require` into the activation entry (mirror `base/scenarios/pvp/control.lua`)
- [x] 1.3 Verify no freeplay hijack; add a dev-only console command to launch manually

## 2. Dedicated arena surface (informed by spike 0.2)

- [x] 2.1 Create the surface at scenario `on_init` with MapGenSettings: `out-of-map` tile autoplace default (bounded void), enemies/resources/decoratives suppressed
- [x] 2.2 Pre-generate the arena footprint chunks (`request_to_generate_chunks` + `force_generate_chunk_requests`) BEFORE tiling/placing
- [x] 2.3 Floor the footprint ONCE at a fixed MAX size with `refined-concrete` (D12: not resized per match); optional outer cliff/water ring as belt-and-suspenders
- [x] 2.4 Move all spawning onto this surface (replace the nauvis assumption in match.lua)

## 3. Behemoth vehicle prototype (pulled forward — its width sizes the pockets)

- [ ] 3.1 Clone `tank`; set `guns = {"bvb-behemoth-gun"}` (drop stock guns); `energy_source = { type = "void" }` (D9); keep/confirm the equipment grid (D10). Record its `collision_box` width (~1.8t) as a CONFIG constant for pocket-gap sizing
- [ ] 3.2 NOT a spidertron (must be blocked by boundary terrain)

## 4. Grounded layout generation (rewrite arena.lua)

- [ ] 4.1 Central hunter hub at arena center (Behemoth spawn + heal anchor)
- [ ] 4.2 Central Builder spawn (shared point; Builders roam/claim freely — no per-builder assignment); state whether hub and Builder spawn are the same point or offset
- [ ] 4.3 Deterministic scattered pockets, MORE than the player count, chunk-aligned, varying sizes on a hub-distance safety gradient (exposed near center, larger/safer toward edges, obscure nooks); seeded, no unsynced randomness
- [ ] 4.4 Each pocket: single-entry choke sized so the vehicle (width from 3.1) cannot pass; reuse the cliff/water boundary helper
- [ ] 4.5 Overlap/fit guard: pockets don't overlap AND the whole layout fits inside the floored footprint; `log()` adjustments
- [ ] 4.6 Regenerate pockets cleanly on restart (footprint/floor persist per D12)

## 5. Behemoth vehicle runtime (highest-risk; own implementer pass)

- [ ] 5.1 Seat the Behemoth player in the vehicle at the hub after the grace period (replace character spawn for the Behemoth); track the vehicle entity in `storage`
- [ ] 5.2 Arm via `car_ammo` (idempotent, armed immediately on spawn); keep the custom ammo category
- [ ] 5.3 Rewrite identity everywhere to `vehicle.get_driver()` + vehicle-type checks: `on_entity_damaged` income + armor mitigation, `scanner_sweep`, and match.lua's death/left handling — none may use `entity.player`/`player.character` for the Behemoth (D11)
- [ ] 5.4 Stats: damage/attack-speed via force modifiers (unchanged); armor via scripted mitigation on the vehicle; max-health via equipment-grid energy-shield tiers (D10)
- [ ] 5.5 Win detection: end match (Builders win) when the tracked Behemoth vehicle is destroyed (`on_entity_died` on it); handle driver ejection; guard the ejected character from tank-explosion splash on the same tick
- [ ] 5.6 Hub heal: passive regen while the vehicle is within the hub radius (D13), on the nth-tick
- [ ] 5.7 Destroy any leftover driverless vehicle on Behemoth disconnect/match end (no entity leak)

## 6. Hiding (baseline)

- [ ] 6.1 Modest vehicle vision radius so it must approach/enter pockets to see them
- [ ] 6.2 Keep base locations off the Behemoth minimap until observed (map fog); confirm Scanner Sweep reveals via `force.chart`
- [ ] 6.3 Do NOT implement in-game occlusion (accepted limitation); note the per-force render-overlay hack as future

## 7. Integration and verification

- [ ] 7.1 Reconcile match.lua: central spawn, arena.generate before spawn, vehicle Behemoth, restart clears pockets + vehicle + fog; ALL prior audit fixes (recipe lockdown, respawn/disconnect handling, etc.) preserved
- [ ] 7.2 Out-of-bounds fallback: periodic sweep teleports any player/vehicle outside the footprint back in (D14)
- [ ] 7.3 Keep the old character-based Behemoth code until the tank model is confirmed in-engine (D15 rollback)
- [ ] 7.4 Determinism: seed/index-based layout, all state in `storage`, single-registrar events (new events like `on_player_driving_changed_state` wired only in control.lua)
- [ ] 7.5 `luac5.4 -p` all Lua + `luacheck .` (0/0); `openspec validate arena-generation`
- [ ] 7.6 Update `docs/verification.md`: the spikes, uniform bounded surface, hub + heal, more-pockets-than-players, single-entry chokes block the tank, tank can't slip side gaps, hiding-by-search, restart clean, out-of-bounds fallback, cliff-vs-water decision
