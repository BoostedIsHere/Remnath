-- Wires the DodgeEvent remote to per-player DodgeService instances.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local controllersFolder = script.Parent:WaitForChild("Controllers")
local DodgeService = require(controllersFolder:WaitForChild("DodgeService"))

local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local DodgeEvent = remotes:FindFirstChild("DodgeEvent") or Instance.new("RemoteEvent")
DodgeEvent.Name = "DodgeEvent"
DodgeEvent.Parent = remotes

local services = {}

local function getService(player)
	local svc = services[player]
	if not svc then
		svc = DodgeService.new(player)
		services[player] = svc
	end
	return svc
end

Players.PlayerRemoving:Connect(function(player)
	services[player] = nil
end)

DodgeEvent.OnServerEvent:Connect(function(player, direction, timestamp)
	local svc = getService(player)
	svc:HandleDodgeRequest(direction, timestamp)
end)
