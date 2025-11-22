-- Wires BlockEvent/ParryEvent to per-player BlockParryService instances.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local controllersFolder = script.Parent:WaitForChild("Controllers")
local BlockParryService = require(controllersFolder:WaitForChild("BlockParryService"))

local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local BlockEvent = remotes:FindFirstChild("BlockEvent") or Instance.new("RemoteEvent")
BlockEvent.Name = "BlockEvent"
BlockEvent.Parent = remotes

local ParryEvent = remotes:FindFirstChild("ParryEvent") or Instance.new("RemoteEvent")
ParryEvent.Name = "ParryEvent"
ParryEvent.Parent = remotes

local services = {}

local function getService(player)
	local svc = services[player]
	if not svc then
		svc = BlockParryService.new(player)
		services[player] = svc
	end
	return svc
end

Players.PlayerAdded:Connect(function(player)
	getService(player)
end)

Players.PlayerRemoving:Connect(function(player)
	BlockParryService.Remove(player)
	services[player] = nil
end)

for _, plr in ipairs(Players:GetPlayers()) do
	getService(plr)
end

print("[BlockParryServerInit] Ready: remotes wired, services prewarmed for", #Players:GetPlayers(), "players")

BlockEvent.OnServerEvent:Connect(function(player, action)
	local svc = getService(player)
	svc:HandleBlockRequest(action)
end)

ParryEvent.OnServerEvent:Connect(function(player, timestamp)
	local svc = getService(player)
	svc:HandleParryRequest(timestamp)
end)
