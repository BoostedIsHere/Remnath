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

M1Event.OnServerEvent:Connect(function(player, swingIndex)
	local character = player.Character
	if not character then return end

	local controller = getController(character)
	if not controller then return end

	if type(swingIndex) ~= "number" then
		swingIndex = 1
	end

	controller:M1Attack(swingIndex)
end)
