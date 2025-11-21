-- WeaponModule: returns per-tool combat config.
-- Centralizes configs so server listeners and controllers share the same numbers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponModule = {}

local weaponsFolder = ReplicatedStorage:WaitForChild("Weapons")
local fistsConfigModule = weaponsFolder:WaitForChild("Fists"):WaitForChild("Config")

local Weapons = {
	Fists = require(fistsConfigModule),
}

function WeaponModule.GetWeaponConfig(tool)
	if not tool then return nil end
	return Weapons[tool.Name]
end

return WeaponModule

