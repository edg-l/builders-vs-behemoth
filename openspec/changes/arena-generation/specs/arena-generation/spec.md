## ADDED Requirements

### Requirement: Scenario entry point
The system SHALL be launchable as a bundled scenario ("New Game -> Scenarios"), and the mode SHALL NOT auto-run on an arbitrary freeplay world merely because the mod is enabled.

#### Scenario: Launch from the scenario list
- **WHEN** a player starts the bundled scenario
- **THEN** the mode initializes (forces, arena surface, lobby)

#### Scenario: No freeplay hijack
- **WHEN** the mod is enabled but a normal freeplay game is started
- **THEN** the mode does not take over that game

### Requirement: Dedicated bounded arena surface
The system SHALL run the match on a dedicated surface that is a small, bounded region floored uniformly, with native enemies and resource clutter suppressed.

#### Scenario: Uniform bounded playfield
- **WHEN** the arena surface is created at match setup
- **THEN** the playable region is enclosed by an impassable boundary, floored with a single uniform tile, and free of biters and stray resources

#### Scenario: Bounded search
- **WHEN** the Behemoth hunts
- **THEN** it can traverse the entire finite playfield and cannot leave it into open/infinite terrain

### Requirement: Central hunter hub
The system SHALL provide a fixed central hub where the Behemoth spawns, can heal, and can shop, and from which it radiates outward to hunt.

#### Scenario: Hub anchors the hunter
- **WHEN** the Behemoth spawns after the grace period
- **THEN** it appears at the central hub and can return there to heal/shop

### Requirement: Builder spawn and pocket claiming
The system SHALL spawn Builders at a shared central location and let each Builder roam the arena to build in a pocket of their choice; the arena SHALL contain more pockets than there are Builders.

#### Scenario: Roam and claim
- **WHEN** a match starts
- **THEN** Builders spawn centrally and can move out to build in any pocket, with some pockets left unclaimed

#### Scenario: More pockets than players
- **WHEN** the arena is generated for N Builders
- **THEN** it contains more than N pockets, so hiding-spot choice is real

### Requirement: Varying single-entry pockets on a gradient
The system SHALL generate pockets of varying size distributed by risk/safety — smaller/exposed near the hub, larger toward the edges, with obscure off-path spots — each a single-entry choke sized so the Behemoth is confined to the gap.

#### Scenario: Size and safety vary
- **WHEN** pockets are generated
- **THEN** their sizes and hub-distances vary, giving exposed-but-central and safe-but-remote options

#### Scenario: Single entry per pocket
- **WHEN** a pocket is generated
- **THEN** it is enclosed except for one choke the Builder can wall, and the Behemoth can only enter through that choke

### Requirement: Deterministic generation and restart
The system SHALL generate the arena deterministically (identical across multiplayer peers) and SHALL restore a clean arena when a match restarts.

#### Scenario: Peers agree
- **WHEN** the arena is generated in multiplayer
- **THEN** every peer produces the identical arena with no desync

#### Scenario: Clean restart
- **WHEN** a match restarts
- **THEN** the arena is regenerated to a correct clean state with no leftover terrain from the previous match

### Requirement: Hiding by search and map fog
The system SHALL make Builder bases discoverable only by the Behemoth physically approaching or scanning them, and SHALL keep base locations off the Behemoth's minimap until observed. The system SHALL NOT be required to occlude bases that are already within the Behemoth's live vision (an accepted engine limitation).

#### Scenario: Must search to find
- **WHEN** a Builder base is outside the Behemoth's vision and unscanned
- **THEN** its location is not revealed on the Behemoth's map until the Behemoth approaches or uses Scanner Sweep

#### Scenario: Scan to peek
- **WHEN** the Behemoth uses Scanner Sweep on an area
- **THEN** that area is revealed to the Behemoth temporarily
