## ADDED Requirements

### Requirement: Structures hidden outside live vision
The system SHALL rely on Factorio fog of war so that Builder structures located outside the Behemoth's live vision are not visible to the Behemoth, even in previously charted areas.

#### Scenario: Base built out of sight stays hidden
- **WHEN** a Builder constructs structures in an area the Behemoth is not currently observing
- **THEN** those structures are not shown to the Behemoth until the area is observed again

#### Scenario: Walking into vision reveals
- **WHEN** the Behemoth moves within its vision range of a hidden Builder structure
- **THEN** that structure becomes visible to the Behemoth

### Requirement: No elevation-based vision
The system SHALL NOT depend on terrain elevation or line-of-sight for concealment, since Factorio has none; concealment SHALL be governed by vision range and charting only.

#### Scenario: Concealment is distance/observation based
- **WHEN** a Builder relies on hiding
- **THEN** their safety depends on staying outside the Behemoth's vision and scans, not on high ground or obstacles blocking sight

### Requirement: Reveal via scanning
The system SHALL make hidden Builder structures discoverable through the Behemoth's Scanner Sweep, consistent with the behemoth-combat capability.

#### Scenario: Scan exposes a hidden base
- **WHEN** the Behemoth scans an area containing hidden Builder structures
- **THEN** those structures are revealed to the Behemoth for the duration the area remains observed
