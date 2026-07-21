## ADDED Requirements

### Requirement: Shop panel
The system SHALL provide a GUI shop panel through which a player spends currency, showing the items available to that player's role and their costs.

#### Scenario: Opening the shop
- **WHEN** a player opens the shop
- **THEN** a panel appears listing purchasable items appropriate to their role with prices

#### Scenario: Role-appropriate contents
- **WHEN** a Behemoth and a Builder each open the shop
- **THEN** each sees only the purchases valid for their own role

### Requirement: Balance display
The system SHALL display the player's current currency balance and keep it updated as the balance changes.

#### Scenario: Balance updates after income
- **WHEN** a player's currency balance changes
- **THEN** the displayed balance reflects the new value

### Requirement: Purchase handling
The system SHALL process a purchase when a player clicks a shop item, deducting the cost only if affordable and applying the item's effect, and SHALL reject unaffordable purchases without deducting currency.

#### Scenario: Affordable purchase
- **WHEN** a player clicks an item they can afford
- **THEN** the cost is deducted, the effect is applied, and the balance display updates

#### Scenario: Unaffordable purchase
- **WHEN** a player clicks an item they cannot afford
- **THEN** no currency is deducted, no effect is applied, and the player is informed
