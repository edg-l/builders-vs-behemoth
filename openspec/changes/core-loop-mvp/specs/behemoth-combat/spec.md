## ADDED Requirements

### Requirement: Damage-to-currency income
The system SHALL grant the Behemoth currency in proportion to the damage it deals to Builder structures, this being the Behemoth's primary income source.

#### Scenario: Damaging a structure pays out
- **WHEN** the Behemoth deals damage to a Builder structure
- **THEN** the Behemoth's currency balance increases in proportion to the damage actually dealt

#### Scenario: Damage to non-structures does not pay
- **WHEN** the Behemoth deals damage to terrain, neutral entities, or a Builder character
- **THEN** no structure-damage currency is awarded for that hit

### Requirement: Behemoth stat progression
The system SHALL let the Behemoth spend currency at the shop to upgrade its combat stats, including damage, attack speed, armor, and maximum health.

#### Scenario: Purchasing a stat upgrade
- **WHEN** the Behemoth buys a stat upgrade it can afford
- **THEN** the cost is deducted and the corresponding stat increases immediately

#### Scenario: Health upgrade preserves current health ratio
- **WHEN** the Behemoth upgrades maximum health
- **THEN** its maximum health increases without setting current health below its pre-upgrade value

### Requirement: Scanner Sweep ability
The system SHALL give the Behemoth a Scanner Sweep ability that temporarily reveals an area of the map, exposing hidden Builder structures within it, subject to a cooldown.

#### Scenario: Revealing an area
- **WHEN** the Behemoth uses Scanner Sweep on a location
- **THEN** that area is charted for the Behemoth force and any Builder structures there become visible

#### Scenario: Cooldown enforced
- **WHEN** the Behemoth uses Scanner Sweep and the ability is on cooldown
- **THEN** the ability does not activate until the cooldown has elapsed
