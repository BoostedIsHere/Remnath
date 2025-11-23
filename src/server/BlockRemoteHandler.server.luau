-- Server-side handler for BlockRemote to authoritatively toggle blocking.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local BlockRemote = remotes:WaitForChild("BlockRemote")

local function setBlocking(player, state)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if state then
		humanoid:SetAttribute("IsBlocking", true)
	else
		humanoid:SetAttribute("IsBlocking", nil)
	end
end

BlockRemote.OnServerEvent:Connect(function(player, state)
	if type(state) ~= "boolean" then
		warn("[BlockRemoteHandler] Invalid payload from", player.Name)
		return
	end

	setBlocking(player, state)
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid:SetAttribute("IsBlocking", nil)
	end)
end)
