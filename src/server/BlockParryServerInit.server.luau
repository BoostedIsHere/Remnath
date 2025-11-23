-- Wires BlockEvent/ParryEvent to per-player BlockParryService instances.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverFolder = script.Parent
local controllersFolder = serverFolder:FindFirstChild("Controllers")
	or game:GetService("ServerScriptService"):WaitForChild("Controllers")

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
		local ctor = BlockParryService and BlockParryService.new
		if type(ctor) == "function" then
			svc = ctor(player)
			services[player] = svc
		else
			warn("[BlockParryServerInit] BlockParryService.new missing; block/parry disabled for", player)
			return nil
		end
	end
	return svc
end

Players.PlayerAdded:Connect(function(player)
	getService(player)
end)

Players.PlayerRemoving:Connect(function(player)
	if BlockParryService and type(BlockParryService.Remove) == "function" then
		BlockParryService.Remove(player)
	end
	services[player] = nil
end)

for _, plr in ipairs(Players:GetPlayers()) do
	getService(plr)
end

print("[BlockParryServerInit] Ready: remotes wired, services prewarmed for", #Players:GetPlayers(), "players")

BlockEvent.OnServerEvent:Connect(function(player, action)
	local svc = getService(player)
	if svc and type(svc.HandleBlockRequest) == "function" then
		svc:HandleBlockRequest(action)
	end
end)

ParryEvent.OnServerEvent:Connect(function(player, timestamp)
	local svc = getService(player)
	if svc and type(svc.HandleParryRequest) == "function" then
		svc:HandleParryRequest(timestamp)
	end
end)
