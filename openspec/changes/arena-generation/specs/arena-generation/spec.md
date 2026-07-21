## ADDED Requirements

### Requirement: Single-entry Builder pockets
The system SHALL generate, for each Builder, an enclosed defensible pocket bounded by impassable terrain with exactly one entry gap (the choke), created before the Builder can act.

#### Scenario: Pocket has one entry
- **WHEN** the arena is generated for a Builder
- **THEN** the Builder's spawn area is enclosed by impassable terrain except for a single gap wide enough to place a Wall across

#### Scenario: Generated before play
- **WHEN** a match starts
- **THEN** each Builder's pocket exists before the Builder's grace period begins, so they can immediately build inside it

### Requirement: Behemoth confined to the choke
The system SHALL make the pocket boundary impassable to the Behemoth, so the only way it can reach a Builder's base is through the single gap.

#### Scenario: Boundary blocks the hunter
- **WHEN** the Behemoth attempts to reach a pocketed base
- **THEN** it cannot cross the boundary terrain and must pass through the gap

### Requirement: Deterministic layout
The system SHALL place pockets deterministically from each Builder's ordinal, without runtime randomness, so every multiplayer peer generates identical terrain.

#### Scenario: Peers agree
- **WHEN** the arena is generated in a multiplayer game
- **THEN** every peer produces the same pockets at the same positions with no desync

#### Scenario: Integrated with ring spawn
- **WHEN** Builders are spawned around the ring
- **THEN** each Builder starts inside their own pocket centered on their ring position

### Requirement: Restart regeneration
The system SHALL leave the arena in a clean, known state when a match restarts, so a new match's pockets are not corrupted by the previous match's terrain.

#### Scenario: Clean restart
- **WHEN** a match restarts and a new one starts
- **THEN** each Builder again gets a correct single-entry pocket, with no leftover boundary terrain blocking or duplicating the new layout
