--[[
LocalCombatHandler (StarterPlayerScripts)
- Waits for the Fists tool, plays local swing animations on M1.
- Drives client-side Deepwoken-style hitboxes during the active window and fires CombatEvents.M1Event with tool, swing index, and target humanoid.
- Sends block start/stop to CombatEvents.BlockEvent.
- Plays the tool HitSound when this player receives a hitmarker.
Acts as the general client bridge until weapon-specific handlers fully replace it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
animator.Parent = humanoid

-- Wait for tool
local tool
repeat
	tool = player.Backpack:FindFirstChild("Fists") or player.Character:FindFirstChild("Fists")
	task.wait(0.1)
until tool
print("[LocalCombatHandler] Tool found:", tool.Name)

-- If the tool already has its own WeaponClient, skip this generic handler to avoid double hitboxes.
if tool:FindFirstChild("WeaponClient") then
	warn("[LocalCombatHandler] Tool-local WeaponClient present; skipping LocalCombatHandler for", tool.Name)
	return
end

-- Equipped state
local equipped = false
tool.Equipped:Connect(function()
	equipped = true
	print("[LocalCombatHandler] Tool equipped")
end)
tool.Unequipped:Connect(function()
	equipped = false
	print("[LocalCombatHandler] Tool unequipped")
end)

-- Animations
local animFolder = tool:WaitForChild("Animations")
local Config = require(tool:WaitForChild("Config"))
local Punches = {}
for i, animName in ipairs(Config.Combo) do
	local anim = animFolder:WaitForChild(animName)
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action
	Punches[i] = track
end

-- Combo state
local currentSwing = 1
local swinging = false

-- Remotes
local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event = CombatEvents:WaitForChild("M1Event")
local BlockEvent = CombatEvents:WaitForChild("BlockEvent")
local HitmarkerEvent = CombatEvents:WaitForChild("HitmarkerEvent")
local ClientHitbox = require(ReplicatedStorage.Modules:WaitForChild("ClientHitbox"))

-- HitSound inside tool
local hitSound = tool:FindFirstChild("HitSound")
if not hitSound then
	warn("[LocalCombatHandler] No HitSound found in tool:", tool.Name)
end

---------------------------------------------------------------------
-- Client-side hitbox controller (persistent)
---------------------------------------------------------------------
local hitboxController = ClientHitbox.new({
	Tool = tool,
	Character = character,
	Config = Config,
	OnHit = function(hum, position, swingIndex)
		M1Event:FireServer(tool, swingIndex, hum, position)
	end,
	OnFallback = function(swingIndex)
		M1Event:FireServer(tool, swingIndex)
	end,
})

local function getTimingFromConfig(value, swingIndex, legacyTable)
	if type(value) == "table" then
		return value[swingIndex] or value[1]
	end
	if type(value) == "number" then
		return value
	end
	if type(legacyTable) == "table" then
		return legacyTable[swingIndex] or legacyTable[1]
	end
	return nil
end

---------------------------------------------------------------------
-- Mouse1 input: plays animation and runs client hitbox window
---------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not equipped then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if swinging then return end

	swinging = true
	print("[LocalCombatHandler] Swinging", currentSwing)

	local track = Punches[currentSwing]
	if not track then
		warn("[LocalCombatHandler] No track for swing", currentSwing)
		swinging = false
		return
	end

	local windupTime = getTimingFromConfig(Config.WindupTime, currentSwing) or 0
	local activeTime = getTimingFromConfig(Config.ActiveTime, currentSwing, Config.ActiveFrames) or 0.1
	local recoveryTime = getTimingFromConfig(Config.RecoveryTime, currentSwing) or Config.M1Recovery or 0.25
	local swingId = currentSwing

	track:Play()

	task.delay(windupTime, function()
		if not track.IsPlaying or not equipped then return end
		hitboxController:StartSwing(swingId, activeTime)
	end)

	track.Stopped:Once(function()
		swinging = false
		currentSwing += 1
		if currentSwing > #Punches then
			currentSwing = 1
		end
		print("[LocalCombatHandler] Animation finished, next swing:", currentSwing)
	end)

	-- Safety: end the swing even if the animation fails to stop.
	task.delay(windupTime + activeTime + recoveryTime, function()
		if swinging then
			swinging = false
		end
	end)
end)

---------------------------------------------------------------------
-- Block input
---------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.F then
		BlockEvent:FireServer(true)
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if input.KeyCode == Enum.KeyCode.F then
		BlockEvent:FireServer(false)
	end
end)

---------------------------------------------------------------------
-- Hitmarker / HitSound
---------------------------------------------------------------------
HitmarkerEvent.OnClientEvent:Connect(function(attackerPlayer)
	if attackerPlayer ~= player then return end
	if hitSound then
		print("[LocalCombatHandler] Playing hit sound")
		hitSound:Play()
	end
end)
