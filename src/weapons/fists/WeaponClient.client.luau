--[[
Tool-local client for Fists.
- Plays swing animations on M1 and drives client-side Deepwoken-style hitboxes during the active window.
- Fires CombatEvents.M1Event with the tool, swing index, and target humanoid for each new hit.
- Forwards block start/stop to CombatEvents.BlockEvent and plays HitSound on hitmarker.
]]
print("[WeaponClient] FILE VERSION running")

local tool = script.Parent
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event        = CombatEvents:WaitForChild("M1Event")
local BlockEvent     = CombatEvents:WaitForChild("BlockEvent")
local HitmarkerEvent = CombatEvents:WaitForChild("HitmarkerEvent")

local Config = require(tool:WaitForChild("Config"))
local ClientHitbox = require(ReplicatedStorage.Modules:WaitForChild("ClientHitbox"))

-- Animator
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

-- Animations inside tool.Animations (P1, P2, P3, P4)
local animFolder = tool:WaitForChild("Animations")

local attackTracks = {}
for index, animName in ipairs(Config.Combo) do
	local anim = animFolder:WaitForChild(animName)
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action
	attackTracks[index] = track
end

local currentSwing = 1
local swinging     = false
local equipped     = false

local hitSound = tool:FindFirstChild("HitSound")

---------------------------------------------------------------------
-- Hitbox helpers
---------------------------------------------------------------------
-- Persistent hitbox controller
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
-- Equip / Unequip
---------------------------------------------------------------------
tool.Equipped:Connect(function()
	equipped = true
end)

tool.Unequipped:Connect(function()
	equipped = false
	swinging = false
end)

---------------------------------------------------------------------
-- M1 input handler
---------------------------------------------------------------------
local function playM1()
	if not equipped then return end
	if swinging then return end

	local track = attackTracks[currentSwing]
	if not track then
		warn("[WeaponClient] No attack track for swing index", currentSwing)
		return
	end

	swinging = true

	local windupTime = getTimingFromConfig(Config.WindupTime, currentSwing) or 0
	local activeTime = getTimingFromConfig(Config.ActiveTime, currentSwing, Config.ActiveFrames) or 0.1
	local recoveryTime = getTimingFromConfig(Config.RecoveryTime, currentSwing) or Config.M1Recovery or 0.25
	local swingId = currentSwing

	track:Play()

	task.delay(windupTime, function()
		if not track.IsPlaying or not equipped then return end
		hitboxController:StartSwing(swingId, activeTime)
	end)

	track.Stopped:Connect(function()
		swinging = false

		-- simple 4-hit loop
		currentSwing += 1
		if currentSwing > #attackTracks then
			currentSwing = 1
		end
	end)

	task.delay(windupTime + activeTime + recoveryTime, function()
		if swinging then
			swinging = false
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not equipped then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		playM1()
	end
end)

---------------------------------------------------------------------
-- Block input
---------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not equipped then return end

	if input.KeyCode == Enum.KeyCode.F then
		BlockEvent:FireServer(true)
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.F then
		BlockEvent:FireServer(false)
	end
end)

---------------------------------------------------------------------
-- Hitmarker / HitSound
---------------------------------------------------------------------
HitmarkerEvent.OnClientEvent:Connect(function(hitTargetName)
	if not equipped then return end
	if hitSound then
		hitSound:Play()
	end
end)
