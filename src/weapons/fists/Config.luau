-- Centralized tuning for the Fists weapon so both client and server
-- read the same damage/range/timing numbers.
local Config = {}

Config.Name = "Fists"
Config.Combo = {"P1", "P2", "P3", "P4"}

-- Per-swing tuning (mirrors the server-side defaults in WeaponModule).
Config.Damage = {10, 12, 15, 18}
Config.Knockback = {0, 0, 0, 14}               -- studs
Config.ActiveFrames = {0.1, 0.1, 0.12, 0.14}   -- seconds each swing can hit (legacy)
Config.M1Recovery = 0.25                       -- seconds before returning to Idle

-- Shared spatial values
Config.Range = 4                               -- server-side range validation
Config.HitboxSize = Vector3.new(2.5, 2.5, 3)    -- box size for overlap/validation
Config.HitboxOffset = CFrame.new(0, 0, -1)      -- slight forward offset from the attachment (toward the fist edge)
Config.ServerValidationScale = 0.85            -- shrink server recheck hitbox to be stricter
Config.CastType = "Blockcast"                  -- "Blockcast" or "Spherecast"
Config.HitboxRadius = 0                        -- used when CastType is "Spherecast"

-- Timing for Deepwoken-style client hitboxes
Config.WindupTime = 0.1
Config.ActiveTime = 0.12
Config.RecoveryTime = 0.25

Config.Hand = "RightHand"

return Config
