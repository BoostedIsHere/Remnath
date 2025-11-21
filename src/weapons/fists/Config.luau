-- Centralized tuning for the Fists weapon so both client and server
-- read the same damage/range/timing numbers.
local Config = {}

Config.Name = "Fists"
Config.Combo = {"P1", "P2", "P3", "P4"}

-- Per-swing tuning (mirrors the server-side defaults in WeaponModule).
Config.Damage = {10, 12, 15, 18}
Config.Knockback = {0, 0, 0, 14}              -- studs
Config.ActiveFrames = {0.1, 0.1, 0.12, 0.14}  -- seconds each swing can hit
Config.M1Recovery = 0.25                      -- seconds before returning to Idle

-- Shared spatial values
Config.Range = 4                              -- forward offset from HumanoidRootPart
Config.HitboxSize = Vector3.new(2, 2, 2)      -- size of temp hitbox part
Config.Hand = "RightHand"

return Config

