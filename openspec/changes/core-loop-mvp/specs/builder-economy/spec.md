## ADDED Requirements

### Requirement: Generator economy building
The system SHALL provide Builders a placeable Generator that produces currency over time, and each Builder SHALL be able to have at most one active Generator.

#### Scenario: Placing the first Generator
- **WHEN** a Builder places a Generator and has none already
- **THEN** the Generator is created on the Builders force and begins producing currency

#### Scenario: Only one Generator per Builder
- **WHEN** a Builder attempts to place a second Generator while one is active
- **THEN** the placement is rejected and the Builder is informed

#### Scenario: Salvage refund
- **WHEN** a Builder salvages their Generator
- **THEN** it is removed and the Builder may place a new one elsewhere

### Requirement: Generator tier ladder
The system SHALL allow a Builder to upgrade their Generator through a fixed ladder of tiers, where each higher tier increases currency output and costs currency to reach.

#### Scenario: Upgrading a tier
- **WHEN** a Builder upgrades a Generator and can afford the tier cost
- **THEN** the cost is deducted and the Generator's output rate increases to the new tier's rate

#### Scenario: Insufficient funds
- **WHEN** a Builder attempts an upgrade they cannot afford
- **THEN** the upgrade is rejected and currency is unchanged

### Requirement: Currency income tick
The system SHALL grant currency to each Builder on a periodic income tick, proportional to their Generator's current tier output, using game-tick timing.

#### Scenario: Income accrues over time
- **WHEN** an income tick occurs and a Builder has an active Generator
- **THEN** that Builder's currency balance increases by the Generator's per-tick output

#### Scenario: No Generator, no income
- **WHEN** an income tick occurs and a Builder has no active Generator
- **THEN** that Builder's balance does not change from generator income
