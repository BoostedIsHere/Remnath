--[[
Per-character bridge that connects CombatEvents to a CombatController tied
to this character. Expects (player, tool, swingIndex) from LocalCombatHandler.
]]


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatControllerModule = require(ReplicatedStorage.Modules:WaitForChild("CombatController"))
local WeaponConfigs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("WeaponConfigs"))
local BlockParryService = require(ServerScriptService:WaitForChild("Controllers"):WaitForChild("BlockParryService"))

local character = script.Parent
local player = game.Players:GetPlayerFromCharacter(character)
local CombatController = CombatControllerModule.new(character)

local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event = CombatEvents:WaitForChild("M1Event")
local BlockEvent = CombatEvents:WaitForChild("BlockEvent")
local WeaponHitEvent = CombatEvents:WaitForChild("WeaponHitEvent")

local fistsConfig = WeaponConfigs.Fists

M1Event.OnServerEvent:Connect(function(plr, arg2, arg3, arg4, arg5)
	if plr ~= player then return end

	local tool
	local swing = arg3
	local targetHumanoid
	local hitPosition

	if typeof(arg2) == "Instance" and arg2:IsA("Tool") then
		tool = arg2
		if typeof(arg3) == "number" then
			swing = arg3
		end
		if typeof(arg4) == "Instance" and arg4:IsA("Humanoid") then
			targetHumanoid = arg4
		elseif typeof(arg4) == "Vector3" then
			hitPosition = arg4
		end
		if typeof(arg5) == "Vector3" then
			hitPosition = arg5
		end
	elseif typeof(arg2) == "number" then
		swing = arg2
		if typeof(arg3) == "Instance" and arg3:IsA("Humanoid") then
			targetHumanoid = arg3
		elseif typeof(arg3) == "Vector3" then
			hitPosition = arg3
		end
	elseif typeof(arg2) == "Instance" and arg2:IsA("Humanoid") then
		targetHumanoid = arg2
	elseif typeof(arg2) == "Vector3" then
		hitPosition = arg2
	end

	print("[CharacterCombat] M1Event received from", plr.Name)
	CombatController:M1Attack(plr, tool, swing, targetHumanoid, hitPosition)
end)

-- Block events
BlockEvent.OnServerEvent:Connect(function(plr, isBlocking)
	if plr ~= player then return end
	-- Optional: implement blocking logic here
end)

-- Fists attachment-based hit reports
WeaponHitEvent.OnServerEvent:Connect(function(plr, targetModel, weaponName)
	if plr ~= player then
		return
	end
	if weaponName ~= "Fists" then
		return
	end

	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then
		return
	end
	if targetModel == character then
		return
	end

	local targetHumanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return
	end

	local damageValue = fistsConfig.Damage
	local damage = typeof(damageValue) == "table" and damageValue[1] or damageValue or 5
	local blockParryResult

	local defenderService = BlockParryService.GetFromCharacter(targetModel)
	if defenderService then
		blockParryResult = defenderService:ResolveIncomingHit(plr, {})
	end

	if blockParryResult then
		if blockParryResult.parried then
			damage = 0
		elseif blockParryResult.damageMultiplier then
			damage *= blockParryResult.damageMultiplier
		end
	end

	damage = math.max(0, damage)
	if damage > 0 then
		targetHumanoid:TakeDamage(damage)
	end

	if fistsConfig.StunTime and fistsConfig.StunTime > 0 then
		targetHumanoid:SetAttribute("Hitstunned", true)
		task.delay(fistsConfig.StunTime, function()
			if targetHumanoid.Parent then
				targetHumanoid:SetAttribute("Hitstunned", nil)
			end
		end)
	end
end)
