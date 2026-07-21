## ADDED Requirements

### Requirement: Role selection
The system SHALL let each player choose the Builder or Behemoth role before the match starts, and SHALL guarantee exactly one Behemoth per match.

#### Scenario: Player picks Builder
- **WHEN** a player joins and selects "Builder"
- **THEN** the system assigns that player to the Builders force

#### Scenario: Exactly one Behemoth is chosen
- **WHEN** the match starts and one or more players volunteered for Behemoth
- **THEN** the system selects exactly one of them as the Behemoth and assigns the rest to Builders

#### Scenario: No Behemoth volunteer
- **WHEN** the match starts and no player selected Behemoth
- **THEN** the system randomly designates one connected player as the Behemoth

### Requirement: Force setup and hostility
The system SHALL create two forces, Builders and Behemoth, and SHALL make them mutually hostile so their entities attack each other, while all Builders remain allied to one another.

#### Scenario: Forces are mutually hostile
- **WHEN** the forces are created at match start
- **THEN** cease-fire is disabled in BOTH directions between Builders and Behemoth

#### Scenario: Builders do not fight each other
- **WHEN** two Builder players are near each other
- **THEN** neither their units nor turrets target the other Builder

### Requirement: Staggered match start
The system SHALL spawn Builders first and delay the Behemoth's spawn by a configurable head-start interval so Builders can scatter and hide.

#### Scenario: Behemoth head-start delay
- **WHEN** the match begins
- **THEN** Builders can act immediately and the Behemoth spawns only after the head-start interval elapses, with a visible countdown

### Requirement: Win and lose detection
The system SHALL end the match when a side's victory condition is met: the Behemoth wins if all Builders are eliminated; the Builders win if the Behemoth is killed.

#### Scenario: Behemoth victory
- **WHEN** the last living Builder is eliminated
- **THEN** the match ends and the Behemoth is declared the winner

#### Scenario: Builders victory
- **WHEN** the Behemoth is killed
- **THEN** the match ends and the Builders are declared the winners

#### Scenario: Match teardown
- **WHEN** the match ends
- **THEN** the system announces the result to all players and offers to start a new match
