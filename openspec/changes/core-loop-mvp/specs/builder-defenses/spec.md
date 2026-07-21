## ADDED Requirements

### Requirement: Placeable Walls
The system SHALL provide Builders a Wall that is a single placed entity with one health pool, intended to block the Behemoth at chokes.

#### Scenario: Wall blocks the Behemoth
- **WHEN** a Wall stands across a choke and the Behemoth arrives
- **THEN** the Behemoth cannot pass without destroying the Wall

#### Scenario: Wall has a single health pool
- **WHEN** a Wall takes damage
- **THEN** damage is tracked against that one entity's health, not distributed across separate tiles

### Requirement: Wall tier ladder
The system SHALL let a Builder upgrade a Wall in place through a fixed tier ladder, increasing its effective durability, and each tier SHALL be visually distinguishable.

#### Scenario: Upgrade in place
- **WHEN** a Builder upgrades a Wall and can afford it
- **THEN** the Wall is replaced in the same position by the higher tier with increased durability and no gap is opened

#### Scenario: Per-tier visual
- **WHEN** a Wall reaches a given tier
- **THEN** it displays that tier's distinct color/appearance

### Requirement: Placeable Turrets
The system SHALL provide Builders a Turret that automatically attacks the Behemoth (and any Behemoth-force units) within range.

#### Scenario: Turret engages the Behemoth
- **WHEN** the Behemoth enters a Turret's range
- **THEN** the Turret automatically fires at it

#### Scenario: Turret ignores Builders
- **WHEN** another Builder passes within a Turret's range
- **THEN** the Turret does not fire at them

### Requirement: Turret tier ladder
The system SHALL let a Builder upgrade a Turret through a fixed tier ladder that increases its combat effectiveness for a currency cost.

#### Scenario: Turret upgrade
- **WHEN** a Builder upgrades a Turret and can afford it
- **THEN** the cost is deducted and the Turret's damage output increases to the new tier
