--[[
Per-character bridge that connects CombatEvents to a CombatController tied
to this character. Expects (player, tool, swingIndex) from LocalCombatHandler.
]]


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatControllerModule = require(ReplicatedStorage.Modules:WaitForChild("CombatController"))

local character = script.Parent
local player = game.Players:GetPlayerFromCharacter(character)
local CombatController = CombatControllerModule.new(character)

local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event = CombatEvents:WaitForChild("M1Event")
local BlockEvent = CombatEvents:WaitForChild("BlockEvent")

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
