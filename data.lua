-- data.lua -- data-stage entry point for Builders vs Behemoth.
--
-- This is the single place prototype files get required from. The Generator
-- entity (task 3.1), Wall tier ladder (task 4.1), Turret + ammo tier ladder
-- (task 4.1), and the Behemoth's weapon (task 5.1) are defined under
-- prototypes/.

require("prototypes.generator")
require("prototypes.walls")
require("prototypes.turrets")
require("prototypes.behemoth")
