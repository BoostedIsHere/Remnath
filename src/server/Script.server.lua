local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event = CombatEvents:WaitForChild("M1Event")

local CombatControllerModule = require(ReplicatedStorage.Modules:WaitForChild("CombatController"))
local controllers = {}

local function getController(character)
	if not character then return end
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

M1Event.OnServerEvent:Connect(function(player, tool, swingIndex)
	print("[Server] M1Event from", player.Name, "tool =", tool and tool.Name, "swing =", swingIndex)

	local character = player.Character
	if not character then return end

	local controller = getController(character)
	if not controller then return end

	controller:M1Attack(player, tool, swingIndex)
end)
