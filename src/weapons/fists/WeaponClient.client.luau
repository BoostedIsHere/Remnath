--[[
Tool-local client for Fists.
- Plays swing animations on M1 and fires CombatEvents.M1Event on the "Hit" marker (sends swing index only).
- Mirrors LocalCombatHandler so the tool still works if the generic handler is disabled.
- Plays HitSound on hitmarker.
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
local HitmarkerEvent = CombatEvents:WaitForChild("HitmarkerEvent")
local Config = require(tool:WaitForChild("Config"))

-- Animator
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

-- Animations inside tool.Animations (P1, P2, P3, P4)
local animFolder = tool:WaitForChild("Animations")

local attackAnims = {
	[1] = animFolder:WaitForChild("P1"),
	[2] = animFolder:WaitForChild("P2"),
	[3] = animFolder:WaitForChild("P3"),
	[4] = animFolder:WaitForChild("P4"),
}

local attackTracks = {}
local currentSwing = 1
local swinging     = false
local equipped     = false
local activeTrack  = nil
local comboNames = {}
local lastSwingTime = 0
local minSwingGap = 0.6 -- minimum time between punches

local function stopPunchTracks(reason)
	if activeTrack and activeTrack.IsPlaying then
		print("[WeaponClient] Stopping active punch track (" .. tostring(reason) .. ")")
		activeTrack:Stop()
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Animation and comboNames[track.Animation.Name] and track.IsPlaying then
			track:Stop()
		end
	end
end

local hitSound = tool:FindFirstChild("HitSound")

---------------------------------------------------------------------
-- Load animations and hook "Hit" event (fires to server)
---------------------------------------------------------------------
for index, anim in pairs(attackAnims) do
	local track = animator:LoadAnimation(anim)
	attackTracks[index] = track
	comboNames[anim.Name] = true

	-- When animation reaches the "Hit" marker, tell the server
	track:GetMarkerReachedSignal("Hit"):Connect(function(markerName)
		if not equipped then return end
		if markerName == "Hit" then
			-- Fire to server at exact impact time
			M1Event:FireServer(index)
		end
	end)
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
	local now = os.clock()
	if now - lastSwingTime < minSwingGap then
		print("[WeaponClient] M1 blocked: swing gap")
		return
	end
	if humanoid:GetAttribute("IsBlocking") then
		print("[WeaponClient] M1 blocked: currently blocking")
		stopPunchTracks("blocking input")
		return
	end
	if humanoid:GetAttribute("IsDodging") then
		print("[WeaponClient] M1 blocked: currently dodging")
		stopPunchTracks("dodging input")
		return
	end

	local track = attackTracks[currentSwing]
	if not track then
		warn("[WeaponClient] No attack track for swing index", currentSwing)
		return
	end

	swinging = true
	track:Play()
	activeTrack = track

	-- Safety: if blocking is already active (e.g., rapid F+click), stop immediately.
	if humanoid:GetAttribute("IsBlocking") then
		print("[WeaponClient] Force-stopping M1: blocking already active")
		stopPunchTracks("blocking already active")
		return
	end
	if humanoid:GetAttribute("IsDodging") then
		print("[WeaponClient] Force-stopping M1: dodging already active")
		stopPunchTracks("dodging already active")
		return
	end

	track.Stopped:Connect(function()
		swinging = false
		activeTrack = nil
		lastSwingTime = os.clock()

		-- simple 4-hit loop
		currentSwing += 1
		if currentSwing > #attackTracks then
			currentSwing = 1
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not equipped then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if activeTrack and activeTrack.IsPlaying then
			print("[WeaponClient] M1 blocked: prior swing still playing")
			return
		end
		playM1()
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

humanoid.AttributeChanged:Connect(function(attr)
	if attr == "IsBlocking" and humanoid:GetAttribute("IsBlocking") then
		print("[WeaponClient] Blocking engaged; stopping punch tracks")
		stopPunchTracks("blocking attribute")
	end
	if attr == "IsDodging" and humanoid:GetAttribute("IsDodging") then
		print("[WeaponClient] Dodging engaged; stopping punch tracks")
		stopPunchTracks("dodging attribute")
	end
end)
