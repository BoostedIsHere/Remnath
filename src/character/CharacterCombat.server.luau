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

M1Event.OnServerEvent:Connect(function(plr, tool, swing)
	if plr ~= player then return end
	if tool then
		print("[CharacterCombat] M1Event received from", plr.Name)
		CombatController:M1Attack(plr, tool, swing)
	end
end)
