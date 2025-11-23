--[[
LocalCombatHandler (StarterPlayerScripts)
- Waits for the Fists tool, plays local swing animations on M1.
- Fires CombatEvents.M1Event with the tool + swing index exactly when the "Hit" marker/keyframe occurs.
- Plays the tool HitSound when this player receives a hitmarker.
Acts as the general client bridge until weapon-specific handlers fully replace it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

-- Wait for tool
local tool
repeat
	tool = player.Backpack:FindFirstChild("Fists") or player.Character:FindFirstChild("Fists")
	task.wait(0.1)
until tool
print("[LocalCombatHandler] Tool found:", tool.Name)

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
local HitmarkerEvent = CombatEvents:WaitForChild("HitmarkerEvent")

-- HitSound inside tool
local hitSound = tool:FindFirstChild("HitSound")
if not hitSound then
	warn("[LocalCombatHandler] No HitSound found in tool:", tool.Name)
end

---------------------------------------------------------------------
-- FIRE M1Event WHEN THE ANIMATION "Hit" MARKER IS REACHED + DEBUG
---------------------------------------------------------------------
for index, track in ipairs(Punches) do
	-- debug when track starts/stops
	track:GetPropertyChangedSignal("IsPlaying"):Connect(function()
		if track.IsPlaying then
			print(("[LocalCombatHandler] Swing %d started (len = %.2f)"):format(index, track.Length))
		else
			print(("[LocalCombatHandler] Swing %d stopped"):format(index))
		end
	end)

	-- EVENT MARKER "Hit"
	track:GetMarkerReachedSignal("Hit"):Connect(function()
		print("[LocalCombatHandler] MARKER 'Hit' reached on swing", index)

		if not equipped then
			print("[LocalCombatHandler]  - ignoring marker, not equipped")
			return
		end

		print("[LocalCombatHandler] >>> Firing M1Event(tool, index) from MARKER on swing", index)
		M1Event:FireServer(tool, index)
	end)


	-- ALSO listen for a keyframe named "Hit" just in case
	track.KeyframeReached:Connect(function(keyframeName)
		print("[LocalCombatHandler] KEYFRAME reached:", keyframeName, "on swing", index)
		if keyframeName == "Hit" then
			if not equipped then
				print("[LocalCombatHandler]  - ignoring keyframe, not equipped")
				return
			end
			print("[LocalCombatHandler] >>> Firing M1Event(tool, index) from KEYFRAME on swing", index)
			M1Event:FireServer(tool, index)
		end
	end)
end


---------------------------------------------------------------------
-- Mouse1 input: ONLY plays animation, DOES NOT fire remote
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

	track:Play()

	track.Stopped:Once(function()
		swinging = false
		currentSwing += 1
		if currentSwing > #Punches then
			currentSwing = 1
		end
		print("[LocalCombatHandler] Animation finished, next swing:", currentSwing)
	end)
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
