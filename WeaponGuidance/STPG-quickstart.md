OUT OF DATE! Use the sample configuration and documentation for now, I plan to update this eventually.

Allegedly people find the myriad configuration options obscure and confusing. This covers the minimum setup required to get weapons working, with separate sections on advanced topics. I assume basic familiarity with lua syntax.

# Basic configuration
## Set up global variables.
TargetBufferSize`, `TTTIterationThreshold`, and `TTTMaxIterations` can be left at their defaults.

## Set up target lists.
A target list refines target prioritization by adding hard constraints, such as speed and altitude. You should have a target list for every group of weapons you may want to be targeting something different. For each such group, add an entry to the `TargetLists` table. All fields are required--`MainframeIndex`, `MinimumSpeed`, `MaximumSpeed`, `MinimumAltitude`, `MaximumAltitude`, `MaximumRange`, and `TTT`. To start with, `TTT` should be approximately the time it takes the weapon to travel to its maximum range.
## Set up weapons.
This script controls weapons by weapon group; put all sets of weapons you want it to control together in separate groups.
## Set up weapon groups.
Each lua-controlled weapon group should have an entry in this table, indexed by the weapon group number. There are many settings here (documented [elsewhere](https://github.com/Blothorn/FTD/blob/master/WeaponGuidance/STPG.md)), but the following are required:
+ `TargetList`: The name of the associated target list.
+ `AimPointProportion`: Set to 1 for now (see the aimpoint randomization section for details).
+ `MinimumAltitude`/`MaximumAltitude`: Set to large negative/positive numbers if you want to ignore. These are primarily used in aimpoint randomization.
+ `MinimumRange`: These control the actual firing decision.
+ `FiringAngle`: Set to 180 for vertical launch missiles.
+ `Speed`: Generally best to be about 10% below a missile's maximum speed.
+ `LaunchDelay`: The amount of time lost during launch (relative to launching directly at `Speed` pointed toward the intercept point). Will normally be about half a second for direct-fire missiles and 2-3 seconds for vertical launch missiles; it is not important to be exact.
+ `MinimumConvergenceSpeed`: Helps produce sane results when chasing planes faster than the missile. I suggest about `Speed/2`.
+ `IgnoreSpeed`: Missiles travelling below this speed will no longer receive guidance updates, reducing lag. For most missiles this can be anything below launch speed, although vertical missiles with a long thruster delay may need to be as low as 0.
+ `MinimumCruiseAltitude`: Used to prevent missiles launched near the water and targeting a block below the water from submerging too early. Should usually be quite low (3-5m), but increase it if your missiles are hitting the water too early (and lower it if they cannot make the final turn to the target block).
Further options are documented in STPG.md.
## Report problems/bugs.
I (Blothorn) am often in the semi-official teamspeak evenings and can answer questions. Otherwise, you can ask questions or report problems in the [forum thread](http://www.fromthedepthsgame.com/forum/showthread.php?tid=8960).

# Aimpoint randomization.
AI mainframes without an aimpoint card installed target random blocks; a pool of such mainframes can thus be used to generate a pool of potential blocks to target, useful for avoiding missile clumping and aimpoint spoofing. Without any attention, this code will randomize over all aimpoints; to focus on the aimpoints, use the following instructions:
+ Add mainframes: I suggest having 1-2 with aimpoint selection and some number without. Put the aimpoint mainframes at the lowest indices (add the aimpoint mainframes, then replace all the others). You can check indices that by spawning an enemy structure and running [this script](https://raw.githubusercontent.com/Blothorn/FTD/master/Utilities/MainframeIdentification.txt)--aimpoint mainframes will remain constant, others will slowly cycle target blocks.
+ Set `AimPointProportion`: this dictates what proportion of missiles will try to target the aimpoint---1 means all, 0 means none. Other missiles will cycle through the targets of the other mainframes, although they will skip targets outside of the weapon group's minimum and maximum altitude (if any potential aimpoints do satisfy them).
