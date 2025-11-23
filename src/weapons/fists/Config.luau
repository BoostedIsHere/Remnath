-- Centralized tuning for the Fists weapon so both client and server
-- read the same damage/range/timing numbers. Delegates to the shared
-- WeaponConfigs module so all consumers stay in sync.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponConfigs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("WeaponConfigs"))

return WeaponConfigs.Fists
