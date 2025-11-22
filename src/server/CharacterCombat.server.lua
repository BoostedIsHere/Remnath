local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event = CombatEvents:WaitForChild("M1Event")

local CombatControllerModule = require(ReplicatedStorage.Modules:WaitForChild("CombatController"))

local controllers = {}

local function getController(character)
	if not character then return nil end
	if not controllers[character] then
		controllers[character] = CombatControllerModule.new(character)
	end
	return controllers[character]
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		controllers[character] = CombatControllerModule.new(character)
	end)
end)

M1Event.OnServerEvent:Connect(function(player, arg2, arg3, arg4, arg5)
	local character = player.Character
	if not character then return end

	local controller = getController(character)
	if not controller then return end

	local tool
	local swingIndex = arg2
	local targetHumanoid
	local hitPosition

	if typeof(arg2) == "Instance" and arg2:IsA("Tool") then
		tool = arg2
		swingIndex = arg3
		if typeof(arg4) == "Instance" and arg4:IsA("Humanoid") then
			targetHumanoid = arg4
		elseif typeof(arg4) == "Vector3" then
			hitPosition = arg4
		end
		if typeof(arg5) == "Vector3" then
			hitPosition = arg5
		end
	elseif typeof(arg2) == "number" then
		swingIndex = arg2
		if typeof(arg3) == "Instance" and arg3:IsA("Humanoid") then
			targetHumanoid = arg3
		elseif typeof(arg3) == "Vector3" then
			hitPosition = arg3
		end
	elseif typeof(arg2) == "Instance" and arg2:IsA("Humanoid") then
		targetHumanoid = arg2
		swingIndex = 1
	elseif typeof(arg2) == "Vector3" then
		hitPosition = arg2
	end

	if type(swingIndex) ~= "number" then
		swingIndex = 1
	end

	controller:M1Attack(player, tool, swingIndex, targetHumanoid, hitPosition)
end)
