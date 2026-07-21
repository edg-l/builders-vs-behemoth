-- scripts/vision.lua -- hiding/reveal helpers built on Factorio's native
-- fog of war (design D7): no custom "hidden" state to maintain, only the
-- vision-range tuning and the chart-based reveal used by Scanner Sweep.
--
-- Fills task group 6 (spec: hiding-vision).

local M = {}

function M.on_init()
  -- storage.vision = { active_sweeps = {} } -- bookkeeping for timed reveals, if any
end

function M.on_load()
  -- No `game` access here.
end

-- Vision tuning (6.1) ---------------------------------------------------------

function M.configure_behemoth_vision(behemoth_character)
  -- TODO(6.1): set the Behemoth character/unit vision range small enough
  -- that scouting is required (no map-wide reveal).
end

-- Reveal helper used by behemoth.lua's Scanner Sweep (6.3) -------------------

function M.reveal_area(force, surface, position, radius)
  -- TODO(6.3): force.chart(surface, area centered on position with
  -- radius); confirm it exposes hidden structures at scan time (6.2).
end

return M
