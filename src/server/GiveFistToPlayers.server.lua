local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		local backpack = player:WaitForChild("Backpack")
		local fists = ReplicatedStorage:WaitForChild("Weapons"):WaitForChild("Fists"):Clone()
		fists.Parent = backpack
	end)
end)
