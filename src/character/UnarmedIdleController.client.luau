-- StarterCharacterScripts.UnarmedIdleController (LocalScript)
-- Plays a custom unarmed idle when the player has NO tool equipped
-- and is standing still on the ground.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = script.Parent   -- ✅ in StarterCharacterScripts, parent = Character model
local humanoid = character:WaitForChild("Humanoid")


-- Get or create Animator
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

-- Your idle lives here: ReplicatedStorage.Animations.UnarmedIdle
local animFolder = ReplicatedStorage:WaitForChild("Animations")
local idleAnim = animFolder:WaitForChild("UnarmedIdle")

local idleTrack = animator:LoadAnimation(idleAnim)
idleTrack.Priority = Enum.AnimationPriority.Action  -- override default idle

local function hasToolEquipped()
	-- Any Tool parented to the character counts as "equipped"
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return true
		end
	end
	return false
end

local function shouldPlayIdle()
	if humanoid.Health <= 0 then
		return false
	end

	-- not moving?
	local moving = humanoid.MoveDirection.Magnitude > 0.01

	-- on ground?
	local state = humanoid:GetState()
	local inAir = state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall

	-- unarmed, not moving, on ground
	if not hasToolEquipped() and not moving and not inAir then
		return true
	end

	return false
end

local function updateIdle()
	if shouldPlayIdle() then
		if not idleTrack.IsPlaying then
			idleTrack:Play()
		end
	else
		if idleTrack.IsPlaying then
			idleTrack:Stop()
		end
	end
end

-- Update frequently + on events
RunService.RenderStepped:Connect(updateIdle)

character.ChildAdded:Connect(function(child)
	if child:IsA("Tool") then
		updateIdle()
	end
end)

character.ChildRemoved:Connect(function(child)
	if child:IsA("Tool") then
		updateIdle()
	end
end)

humanoid.Running:Connect(function(_speed)
	updateIdle()
end)

humanoid.StateChanged:Connect(function()
	updateIdle()
end)

updateIdle()
