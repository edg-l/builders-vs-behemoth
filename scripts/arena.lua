-- scripts/arena.lua -- scripted single-entry defensible pockets: carves one
-- enclosed, single-gap boundary per Builder around their ring spawn point,
-- before the Builder can act, and tears it down on restart.
--
-- Fills the arena-generation change (spec: arena-generation).
--
-- Geometry note (verified against ~/factorio-data-reference): design.md's
-- D4 describes "a ring of cliff segments"; this module instead builds an
-- axis-aligned SQUARE boundary. `cliff_orientation` is a closed set of 16
-- named values (4 straight, 4 outer-corner, 4 inner-corner, 8 entrance/
-- "-to-none" endpoints -- see base/prototypes/entity/entity-util.lua's
-- `cliff_orientation` table), not a continuous angle, so a true many-sided
-- circular polygon of cliffs cannot be expressed at all -- only rectilinear
-- (axis-aligned, 90-degree-cornered) boundaries are representable. The
-- shipped base game hits this exact same constraint: `create_moat_for_force`
-- in base/script/pvp/pvp.lua builds a square cliff box with a "lengths" loop
-- that omits the segments spanning each opening, using the same 16
-- orientation constants this module reuses below. That is the pattern this
-- module follows -- a square pocket, not a literal circle -- which still
-- satisfies the spec ("enclosed... with exactly one gap"); only D4's
-- cosmetic "ring" wording is adapted, per its own risk note that the
-- pocket/gap math must stay swappable if cliff geometry can't cleanly close.

local M = {}

-- Tunables (placeholders; retune during the first balance pass, see
-- design.md "Open Questions" -- pocket_radius, gap_width, and ring-radius
-- scaling are explicitly called out as TBD numbers, not final).
local CONFIG = {
  -- "cliff" (default) or "water"; switch this one line to fall back to the
  -- water-moat boundary if cliffs don't close cleanly in-engine (design D1).
  boundary_material = "cliff",
  -- Half-width of the square pocket (the boundary sits at +/- pocket_radius
  -- from the pocket center on each axis). Snapped to a multiple of the
  -- 4-tile cliff grid at use (see snapped_pocket_half below).
  pocket_radius = 16,
  -- Width (tiles) of the single entry gap, wide enough to place several
  -- Walls across. Centered on the gap side's midpoint.
  gap_width = 8,
  -- Extra clearance required between adjacent pocket boundaries beyond
  -- 2*pocket_radius, before the overlap guard scales the ring radius up.
  overlap_margin = 4,
  -- Mirrors match.lua's CONFIG.builder_spawn_position (the Builder spawn
  -- ring's center) and CONFIG.builder_spawn_ring_radius's former default
  -- (intentional cross-module duplication of these constants, matching the
  -- existing convention -- see match.lua's builder_starter_kit comment).
  -- match.lua now sources both the spawn position AND the ring radius from
  -- this module via pocket_center, so the two can never drift apart.
  ring_center = { x = 0, y = 0 },
  base_ring_radius = 20,
  -- Mirrors match.lua's CONFIG.behemoth_spawn_position; used only to keep
  -- pocket boundaries from reaching into the Behemoth's own spawn area.
  behemoth_spawn_position = { x = 64, y = 0 },
  behemoth_exclusion_margin = 8,
  surface_name = "nauvis", -- mirrors match.lua's CONFIG.surface_name
  water_tile_name = "water", -- verified base tile name (base/prototypes/tile/tiles.lua)
}

-- Cliff placement grid spacing: cliffs snap to a 4-tile grid and their
-- straight segments are spaced 4 tiles apart along an edge (verified
-- against base/script/pvp/pvp.lua's create_moat_for_force "lengths" loop).
local CELL = 4

-- Maps a perimeter segment's geometric role to the cliff_orientation that
-- closes a square boundary, verified 1:1 against
-- base/script/pvp/pvp.lua's create_moat_for_force (corners + straight
-- edges of its cliff box use exactly these values).
local ROLE_ORIENTATION = {
  north = "east-to-west",
  south = "west-to-east",
  west = "north-to-south",
  east = "south-to-north",
  ["corner-nw"] = "east-to-south",
  ["corner-ne"] = "south-to-west",
  ["corner-sw"] = "north-to-east",
  ["corner-se"] = "west-to-north",
}

-- Small local helpers (private; no other module needs these) ----------------

local function distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function round_to_multiple(value, multiple)
  return math.floor(value / multiple + 0.5) * multiple
end

-- Half-width actually used for placement: CONFIG.pocket_radius snapped to
-- the cliff grid and floored at 2 cells so a straight edge always has at
-- least one interior segment beyond its two corners.
local function snapped_pocket_half()
  return math.max(CELL * 2, round_to_multiple(CONFIG.pocket_radius, CELL))
end

-- Same ordinal-angle formula match.lua's ring spawn used (design D3): index
-- based, never random, identical on every peer.
local function pocket_angle(ordinal, count)
  return (ordinal - 1) * (2 * math.pi / count)
end

-- The ring math match.lua's spawn positions used to compute locally (now
-- owned here so match.lua's spawn and this module's pocket centers can
-- never drift apart -- see the CONFIG.ring_center comment above).
local function ring_position(center, ordinal, count, radius)
  local angle = pocket_angle(ordinal, count)
  return { x = center.x + radius * math.cos(angle), y = center.y + radius * math.sin(angle) }
end

-- Deterministic gap direction (design D3: "gap faces map center, where the
-- Behemoth roams"): picks whichever of the pocket's 4 sides has its outward
-- normal most aligned with the direction back to the ring center.
local function gap_side_for_angle(angle)
  local cos_a, sin_a = math.cos(angle), math.sin(angle)
  if math.abs(cos_a) >= math.abs(sin_a) then
    return (cos_a >= 0) and "west" or "east"
  end
  return (sin_a >= 0) and "north" or "south"
end

-- Ring radius for `count` builders, after two guards (task 2.3 and the
-- Behemoth-spawn exclusion): overlap avoidance can only ever scale the
-- radius UP; the Behemoth-exclusion clamp can then scale it back DOWN, so
-- the latter always wins if the two disagree. Both adjustments are logged
-- (never applied silently) so an in-engine tune knows this ran.
local function effective_ring_radius(count)
  local half = snapped_pocket_half()
  local radius = CONFIG.base_ring_radius

  if count > 1 then
    local min_spacing = 2 * half + CONFIG.overlap_margin
    local spacing = 2 * radius * math.sin(math.pi / count)
    if spacing < min_spacing then
      local scaled = min_spacing / (2 * math.sin(math.pi / count))
      log(
        string.format(
          "[bvb-arena] %d builders: ring radius %.1f gives pocket spacing %.1f (< required %.1f); scaling ring radius to %.1f to avoid overlap",
          count,
          radius,
          spacing,
          min_spacing,
          scaled
        )
      )
      radius = scaled
    end
  end

  local ring_to_behemoth = distance(CONFIG.ring_center, CONFIG.behemoth_spawn_position)
  local max_safe_radius = ring_to_behemoth - half - CONFIG.behemoth_exclusion_margin
  if radius > max_safe_radius then
    log(
      string.format(
        "[bvb-arena] ring radius %.1f would bring a pocket within %d tiles of the Behemoth spawn area; clamping to %.1f",
        radius,
        CONFIG.behemoth_exclusion_margin,
        max_safe_radius
      )
    )
    radius = max_safe_radius
  end

  if radius < half then
    log(
      string.format(
        "[bvb-arena] clamped ring radius %.1f is smaller than the pocket half-width %.1f; flooring to %.1f (check CONFIG.pocket_radius/overlap_margin/behemoth_exclusion_margin)",
        radius,
        half,
        half
      )
    )
    radius = half
  end

  return radius
end

-- Pocket geometry (material-agnostic, task group 2) --------------------------
--
-- Builds the closed (gap-omitted) perimeter of a pocket as an ordered list
-- of { x, y, role } segment descriptors, where role is one of "north" /
-- "south" / "east" / "west" (a straight edge's interior points) or
-- "corner-nw" / "corner-ne" / "corner-sw" / "corner-se" (its four corners).
-- This list is deliberately material-agnostic: cliff placement maps role ->
-- cliff_orientation (ROLE_ORIENTATION above); water placement fills a tile
-- footprint per role (tile_footprint below). `gap_side` names the one
-- straight edge that carries the single entry gap; segments on that edge
-- within `gap_half_width` of the edge's midpoint are omitted entirely, so
-- the returned list already has the gap cut out of it (spec: "exactly one
-- gap").
local function pocket_perimeter(center, half, gap_side, gap_half_width)
  local segments = {}

  segments[#segments + 1] = { x = center.x - half, y = center.y - half, role = "corner-nw" }
  segments[#segments + 1] = { x = center.x + half, y = center.y - half, role = "corner-ne" }
  segments[#segments + 1] = { x = center.x - half, y = center.y + half, role = "corner-sw" }
  segments[#segments + 1] = { x = center.x + half, y = center.y + half, role = "corner-se" }

  for k = -(half - CELL), half - CELL, CELL do
    if not (gap_side == "north" and math.abs(k) <= gap_half_width) then
      segments[#segments + 1] = { x = center.x + k, y = center.y - half, role = "north" }
    end
    if not (gap_side == "south" and math.abs(k) <= gap_half_width) then
      segments[#segments + 1] = { x = center.x + k, y = center.y + half, role = "south" }
    end
    if not (gap_side == "west" and math.abs(k) <= gap_half_width) then
      segments[#segments + 1] = { x = center.x - half, y = center.y + k, role = "west" }
    end
    if not (gap_side == "east" and math.abs(k) <= gap_half_width) then
      segments[#segments + 1] = { x = center.x + half, y = center.y + k, role = "east" }
    end
  end

  return segments
end

-- Boundary placement (isolated behind one helper, task group 3) -------------

-- Cliff implementation: one `cliff` entity per segment, snapped to the
-- 4-tile grid, oriented per its role (see ROLE_ORIENTATION). Tracks every
-- created entity in storage.arena so clear_boundary can destroy them all on
-- restart.
local function place_cliff_boundary(surface, segments)
  for _, segment in ipairs(segments) do
    local entity = surface.create_entity({
      name = "cliff",
      position = { x = segment.x, y = segment.y },
      cliff_orientation = ROLE_ORIENTATION[segment.role],
    })
    if entity and entity.valid then
      storage.arena.cliff_entities[#storage.arena.cliff_entities + 1] = entity
    end
  end
end

-- Fallback (D1): a water moat via set_tiles, equally impassable, with no
-- grid/orientation constraints. Each segment's anchor point covers a
-- CELLxCELL tile footprint (a strip along the edge for "north"/"south"/
-- "east"/"west" roles, a full block for corners) so adjacent segments'
-- footprints exactly tile the perimeter with no gaps, matching the same
-- CELL spacing the cliff segments use.
local function tile_footprint(segment)
  local tiles = {}
  local x, y, role = segment.x, segment.y, segment.role
  if role == "north" or role == "south" then
    for dx = -(CELL / 2), (CELL / 2) - 1 do
      tiles[#tiles + 1] = { x = x + dx, y = y }
    end
  elseif role == "east" or role == "west" then
    for dy = -(CELL / 2), (CELL / 2) - 1 do
      tiles[#tiles + 1] = { x = x, y = y + dy }
    end
  else -- corner-*
    for dx = -(CELL / 2), (CELL / 2) - 1 do
      for dy = -(CELL / 2), (CELL / 2) - 1 do
        tiles[#tiles + 1] = { x = x + dx, y = y + dy }
      end
    end
  end
  return tiles
end

-- Records each original tile (in storage.arena) before overwriting it, so
-- clear_boundary can revert the moat to its pre-match terrain on restart
-- (task 3.2). De-duplicates by position since corner footprints overlap
-- their neighboring edges' footprints.
local function place_water_boundary(surface, segments)
  local tiles_to_set = {}
  local seen = {}
  for _, segment in ipairs(segments) do
    for _, tile_position in ipairs(tile_footprint(segment)) do
      local key = tile_position.x .. ":" .. tile_position.y
      if not seen[key] then
        seen[key] = true
        local original = surface.get_tile(tile_position.x, tile_position.y)
        storage.arena.original_tiles[#storage.arena.original_tiles + 1] = {
          x = tile_position.x,
          y = tile_position.y,
          name = original.name,
        }
        tiles_to_set[#tiles_to_set + 1] =
          { name = CONFIG.water_tile_name, position = { x = tile_position.x, y = tile_position.y } }
      end
    end
  end
  surface.set_tiles(tiles_to_set)
end

-- The one helper both materials go through (task group 3): swap
-- CONFIG.boundary_material to pick an implementation without touching the
-- pocket/gap geometry above.
local function place_boundary(surface, segments)
  if CONFIG.boundary_material == "water" then
    place_water_boundary(surface, segments)
  else
    place_cliff_boundary(surface, segments)
  end
end

-- Module API entry points ----------------------------------------------------

function M.on_init()
  storage.arena.cliff_entities = {} -- array of LuaEntity (cliff material)
  storage.arena.original_tiles = {} -- array of { x, y, name } (water material, for restart revert)
end

function M.on_load()
  -- No `game` access here.
end

-- Pocket geometry (task 2.1) --------------------------------------------------

-- The `ordinal`-th of `count` Builders' pocket center. Reuses the exact
-- same ring math match.lua's builder spawn uses (design D3), including the
-- overlap/Behemoth-exclusion-adjusted radius, so a Builder's spawn point and
-- their pocket's center always coincide (task 4.2) as long as callers pass
-- the same (ordinal, count) match.lua's spawn loop does.
function M.pocket_center(ordinal, count)
  return ring_position(CONFIG.ring_center, ordinal, count, effective_ring_radius(count))
end

-- Integration (task group 4) --------------------------------------------------

-- Carves one pocket per Builder ordinal in `builder_indices` (the same
-- sorted array match.lua's start_match builds, so #builder_indices is the
-- Builder count and ordinals match spawn_builder's). Call this BEFORE the
-- spawn loop so Builders spawn inside their own, already-placed pocket.
function M.generate(builder_indices)
  local surface = game.surfaces[CONFIG.surface_name] or game.surfaces[1]
  if not surface then
    return
  end
  local count = #builder_indices
  if count == 0 then
    return
  end

  local half = snapped_pocket_half()
  local gap_half_width = CONFIG.gap_width / 2

  for ordinal = 1, count do
    local center = M.pocket_center(ordinal, count)
    local gap_side = gap_side_for_angle(pocket_angle(ordinal, count))
    local segments = pocket_perimeter(center, half, gap_side, gap_half_width)
    place_boundary(surface, segments)
  end
end

-- Teardown (task 3.3), invoked from match.lua's restart_match (task 4.3) so
-- a new match starts from clean terrain: destroys every tracked cliff
-- entity and reverts every recorded water tile to what it was before this
-- module overwrote it, then clears storage.arena.
function M.clear_boundary()
  local surface = game.surfaces[CONFIG.surface_name] or game.surfaces[1]

  for _, entity in pairs(storage.arena.cliff_entities) do
    if entity and entity.valid then
      entity.destroy()
    end
  end
  storage.arena.cliff_entities = {}

  if surface and #storage.arena.original_tiles > 0 then
    local revert_tiles = {}
    for _, tile in ipairs(storage.arena.original_tiles) do
      revert_tiles[#revert_tiles + 1] = { name = tile.name, position = { x = tile.x, y = tile.y } }
    end
    surface.set_tiles(revert_tiles)
  end
  storage.arena.original_tiles = {}
end

return M
