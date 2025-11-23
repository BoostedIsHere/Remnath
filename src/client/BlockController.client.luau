local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local blockRemote = remotes:WaitForChild("BlockRemote")

local animations = ReplicatedStorage:WaitForChild("Animations")
local basicCombatAnims = animations:WaitForChild("BasicCombat")
local blockAnimation = basicCombatAnims:WaitForChild("Block")

local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
local blockAT = animator:LoadAnimation(blockAnimation)

local isBlocking = false
local originalWalkSpeed = humanoid.WalkSpeed
local DEBUG_TAG = "[BlockController]"

local function startBlock()
	if isBlocking or not humanoid or humanoid.Health <= 0 then
		return
	end

	isBlocking = true
	originalWalkSpeed = humanoid.WalkSpeed

	humanoid:SetAttribute("IsBlocking", true)
	blockRemote:FireServer(true)

	if blockAT then
		blockAT:Play()
	end

	-- Slow movement while blocking.
	humanoid.WalkSpeed = math.max(6, originalWalkSpeed * 0.6)
	print(DEBUG_TAG, "Started blocking")
end

local function stopBlock()
	if not isBlocking or not humanoid then
		return
	end

	isBlocking = false
	humanoid:SetAttribute("IsBlocking", nil)
	blockRemote:FireServer(false)

	if blockAT and blockAT.IsPlaying then
		blockAT:Stop()
	end

	if originalWalkSpeed then
		humanoid.WalkSpeed = originalWalkSpeed
	end

	print(DEBUG_TAG, "Stopped blocking")
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		startBlock()
	end
end)

UserInputService.InputEnded:Connect(function(input, gpe)
	if gpe then
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		stopBlock()
	end
end)

player.CharacterAdded:Connect(function(char)
	-- Rebind character/humanoid/animator when respawning.
	character = char
	humanoid = character:WaitForChild("Humanoid")
	animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	blockAT = animator:LoadAnimation(blockAnimation)
	originalWalkSpeed = humanoid.WalkSpeed
	isBlocking = false
	humanoid:SetAttribute("IsBlocking", nil)
end)

print(DEBUG_TAG, "Loaded")
