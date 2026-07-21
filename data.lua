-- data.lua -- data-stage entry point for Builders vs Behemoth.
--
-- This is the single place prototype files get required from. The Generator
-- entity (task 3.1), Wall tier ladder (task 4.1), and Turret + ammo tier
-- ladder (task 4.1) are defined under prototypes/; the Behemoth entity
-- lands in a later task group (5.1).

require("prototypes.generator")
require("prototypes.walls")
require("prototypes.turrets")
-- require("prototypes.behemoth")
