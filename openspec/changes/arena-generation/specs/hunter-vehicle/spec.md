## ADDED Requirements

### Requirement: Behemoth is a wide ground vehicle
The system SHALL make the Behemoth a player-controlled ground vehicle roughly two tiles wide that is blocked by the arena's boundary terrain and by walls, so it cannot cross pocket boundaries and is confined to chokes.

#### Scenario: Confined to the choke
- **WHEN** the Behemoth approaches a pocket
- **THEN** it cannot cross the boundary terrain or squeeze through a one-tile side gap, and can only enter through a wide-enough choke

#### Scenario: Not a wall-ignorer
- **WHEN** the Behemoth encounters cliffs, water, or walls
- **THEN** it is stopped by them (it is not a unit that steps over terrain)

### Requirement: Vehicle armament and progression
The system SHALL arm the Behemoth vehicle and apply its purchased upgrades to the vehicle, preserving the existing progression (damage, attack speed, armor, health) and its damage-to-currency income.

#### Scenario: Armed and firing
- **WHEN** the Behemoth vehicle is spawned
- **THEN** it is armed and can deal damage to Builder structures, earning currency proportional to damage dealt

#### Scenario: Upgrades apply to the vehicle
- **WHEN** the Behemoth buys a stat upgrade
- **THEN** the effect is applied to the vehicle (damage/attack-speed via its weapon, and armor/health via a vehicle-appropriate mechanism)

### Requirement: Vehicle-based win detection
The system SHALL detect the Behemoth's defeat by the destruction of its vehicle, not by a character death.

#### Scenario: Killing the vehicle wins for Builders
- **WHEN** the Behemoth vehicle is destroyed
- **THEN** the match ends with a Builder victory, even though the player is ejected rather than killed
