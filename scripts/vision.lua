-- scripts/vision.lua -- hiding/reveal helpers built on Factorio's native
-- fog of war (design D7): no custom "hidden" state to maintain, only the
-- vision-range tuning and the chart-based reveal used by Scanner Sweep.
--
-- Fills task group 6 (spec: hiding-vision).

local M = {}

function M.on_init()
  -- No bookkeeping needed: reveal_area (6.3) is a stateless wrapper around
  -- LuaForce.chart, and configure_behemoth_vision (6.1) has no state to
  -- persist either (see the constraint documented on that function below).
  -- storage.vision stays an empty table (seeded by control.lua); this
  -- module keeps the namespace reserved for future reveal-helper state, per
  -- design D9, without inventing bookkeeping it doesn't need yet.
end

function M.on_load()
  -- No `game` access here.
end

-- Vision tuning (6.1) ---------------------------------------------------------
--
-- CONSTRAINT (flagged per task 6.1): Factorio 2.0 does not expose a
-- moddable "vision range" for character entities, at either the data stage
-- or the runtime API.
--   - `CharacterPrototype` (data stage) has no vision/sight-radius field
--     comparable to `radar`'s `max_distance_of_sector_revealed` /
--     `max_distance_of_nearby_sector_revealed`; those fields exist only on
--     the radar prototype.
--   - `LuaEntity` (runtime) exposes no `vision_distance` (or equivalent)
--     property for characters either; the only runtime lever affecting fog
--     of war for a force is `LuaForce.chart`/`chart_all` (an explicit,
--     one-shot reveal -- what `reveal_area` below uses for Scanner Sweep),
--     not a standing "vision radius" a character carries around.
--   - The live-vs-charted chunk distinction that "walking near a chunk
--     reveals it live, but only until you leave" IS how vanilla Factorio
--     already behaves for any player-controlled character: the engine
--     reveals a bounded radius of chunks around a walking character (not
--     the whole map), and previously-charted-but-unwatched chunks fall back
--     to their last-known static snapshot once the character leaves --
--     exactly the concealment behavior the hiding-vision spec wants.
--
-- Given that, the closest correct implementation (per the phase brief's own
-- sanctioned fallback: "relying on default character vision") is to NOT
-- attempt to fabricate a vision-range override that the platform doesn't
-- support, and instead rely on the default vanilla character vision
-- radius, which already satisfies "no map-wide reveal" / "scouting is
-- required" without any extra code. This function exists as the agreed
-- seam (in case a real lever is ever found, e.g. a future Factorio API, or
-- a deliberate future redesign using an attached invisible radar entity --
-- rejected here as over-engineering beyond "configure vision range") and as
-- a defensive validation point; it intentionally does not mutate any game
-- state today.
--
-- Follow-up (not wired by this module, see control.lua/match.lua notes):
-- nothing currently calls this function. The natural call site is
-- scripts/match.lua's `spawn_behemoth`, right after the Behemoth's
-- character is created, but match.lua is out of scope for this phase.
-- Wiring it into control.lua's existing on_nth_tick(60) handler was
-- considered and rejected: since the function is a no-op given the
-- constraint above, invoking it periodically would do real work for no
-- functional benefit; wire it only if a real vision-setting API is found.
function M.configure_behemoth_vision(behemoth_character)
  if not (behemoth_character and behemoth_character.valid) then
    return false
  end
  -- Intentionally no-op: see constraint above. Default character vision
  -- already applies; there is nothing further to configure.
  return true
end

-- Reveal helper used by behemoth.lua's Scanner Sweep (6.3) -------------------
--
-- force.chart(surface, area) charts (permanently reveals, per Factorio's
-- fog-of-war model) the given area for `force`, exposing whatever is
-- currently there -- including Builder structures that were hidden because
-- their chunk was uncharted or charted-but-not-currently-visible. `area` is
-- a BoundingBox built from a square of side `2 * radius` centered on
-- `position` (matches behemoth.lua's call: `CONFIG.scanner_sweep_radius`
-- tiles, the caller's tunable -- this module does not duplicate that
-- number).
--
-- No timed re-hide is implemented here: per design D7, fog of war re-hides
-- the area naturally once it leaves the Behemoth's live vision again (the
-- chunk reverts to its last-charted static snapshot, which will show
-- whatever was there at chart time until re-observed) -- a custom hide
-- timer would fight the platform for no gameplay gain.
function M.reveal_area(force, surface, position, radius)
  if not (force and surface and surface.valid and position and radius) then
    return
  end
  local x = position.x or position[1]
  local y = position.y or position[2]
  local area = {
    left_top = { x = x - radius, y = y - radius },
    right_bottom = { x = x + radius, y = y + radius },
  }
  force.chart(surface, area)
end

--[[
Test case (6.2) -- no Factorio install on this dev machine, so this is a
documented in-engine verification procedure, NOT an automated/passing test.
Run this manually on the actual game or headless server once the mod loads.

Scenario A -- structure built out of sight stays hidden
  1. Start a match with at least one Builder and the Behemoth (role-select
     GUI, task 2.2/2.3).
  2. As a Builder, walk far enough from the Behemoth's spawn/current
     position that the area is not currently charted (or was charted long
     ago and the Behemoth has not returned since).
  3. Place a Wall, Turret, or Generator there.
  4. Switch to (or spectate) the Behemoth. Open the map view / walk the
     Behemoth near that area but NOT into live vision range (i.e. stay
     several chunks away).
  Expected: the placed structure(s) do not appear to the Behemoth. If the
  chunk was never charted for the `behemoth` force, it shows fog-of-war
  black. If it was charted earlier (e.g. the Behemoth walked through
  before the structure was built) but is not currently visible, it shows
  the last-known (structure-less) snapshot.

Scenario B -- walking into vision reveals
  1. From the end state of Scenario A, walk the Behemoth's character
     directly toward the hidden structure until it comes within the
     Behemoth's normal (default, unmodified per 6.1) live-vision radius.
  Expected: once within live vision, the structure becomes visible to the
  Behemoth in real time, matching its current state (health, tier, etc.).
  Walk away again and confirm the chunk falls back to a static snapshot
  (further changes Builders make there after the Behemoth leaves should NOT
  be visible until re-observed or re-scanned).

Scenario C -- Scanner Sweep reveals a hidden base
  1. Repeat Scenario A's setup (hidden structure out of live vision, and
     ideally in an uncharted or stale-charted chunk).
  2. As the Behemoth, trigger Scanner Sweep (behemoth.scanner_sweep,
     via the shop once task 7.4 wires it) targeting a position within
     `CONFIG.scanner_sweep_radius` of the hidden structure.
  Expected: immediately after the sweep, the structure and its current
  state become visible to the Behemoth (via `reveal_area` -> `force.chart`)
  even though the Behemoth's character never walked there. Confirm the
  reveal is a live snapshot at scan time (per spec: "revealed ... for the
  duration the area remains observed") -- walking away afterward should let
  the area fall back to fog-of-war exactly as in Scenario B.

Report results (pass/fail per scenario) back into this file or the
project's tracking once run; do not mark 6.2 as verified based on
code-reading alone.
--]]

return M
