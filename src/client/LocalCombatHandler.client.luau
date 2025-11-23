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

-- Remotes
local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event = CombatEvents:WaitForChild("M1Event")
local HitmarkerEvent = CombatEvents:WaitForChild("HitmarkerEvent")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

local tool = nil
local equipped = false
local Punches = {}
local comboNames = {}
local currentSwing = 1
local swinging = false
local activeTrack = nil
local hitSound = nil
local punchEventConns = {}
local lastSwingTime = 0
local minSwingGap = 0.6 -- minimum time between punches

local function bindTool()
	-- Wait for the Fists tool (new instance after respawn too)
	repeat
		tool = player.Backpack:FindFirstChild("Fists") or player.Character:FindFirstChild("Fists")
		task.wait(0.1)
	until tool
	print("[LocalCombatHandler] Tool bound:", tool.Name)

	equipped = false
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
	Punches = {}
	comboNames = {}
	minSwingGap = 0.6
	for i, animName in ipairs(Config.Combo) do
		local anim = animFolder:WaitForChild(animName)
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		Punches[i] = track
		comboNames[animName] = true
	end

	-- HitSound inside tool
	hitSound = tool:FindFirstChild("HitSound")
	if not hitSound then
		warn("[LocalCombatHandler] No HitSound found in tool:", tool.Name)
	end

	-- Reset state
	currentSwing = 1
	swinging = false
	activeTrack = nil
end

bindTool()

local function hookPunchEvents()
	-- Clear previous connections
	for _, conn in ipairs(punchEventConns) do
		conn:Disconnect()
	end
	punchEventConns = {}

	for index, track in ipairs(Punches) do
		table.insert(punchEventConns, track:GetPropertyChangedSignal("IsPlaying"):Connect(function()
			if track.IsPlaying then
				print(("[LocalCombatHandler] Swing %d started (len = %.2f)"):format(index, track.Length))
			else
				print(("[LocalCombatHandler] Swing %d stopped"):format(index))
			end
		end))

		table.insert(punchEventConns, track:GetMarkerReachedSignal("Hit"):Connect(function()
			print("[LocalCombatHandler] MARKER 'Hit' reached on swing", index)

			if not equipped then
				print("[LocalCombatHandler]  - ignoring marker, not equipped")
				return
			end

			print("[LocalCombatHandler] >>> Firing M1Event(tool, index) from MARKER on swing", index)
			M1Event:FireServer(tool, index)
		end))

		table.insert(punchEventConns, track.KeyframeReached:Connect(function(keyframeName)
			print("[LocalCombatHandler] KEYFRAME reached:", keyframeName, "on swing", index)
			if keyframeName == "Hit" then
				if not equipped then
					print("[LocalCombatHandler]  - ignoring keyframe, not equipped")
					return
				end
				print("[LocalCombatHandler] >>> Firing M1Event(tool, index) from KEYFRAME on swing", index)
				M1Event:FireServer(tool, index)
			end
		end))
	end
end

hookPunchEvents()

local function stopPunchTracks(reason)
	if activeTrack and activeTrack.IsPlaying then
		print("[LocalCombatHandler] Stopping active punch track (" .. tostring(reason) .. ")")
		activeTrack:Stop()
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Animation and comboNames[track.Animation.Name] and track.IsPlaying then
			track:Stop()
		end
	end
end

-- Remotes
-- HitSound inside tool set in bindTool
---------------------------------------------------------------------
-- Mouse1 input: ONLY plays animation, DOES NOT fire remote
---------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not equipped then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if swinging then return end
	if activeTrack and activeTrack.IsPlaying then
		print("[LocalCombatHandler] M1 blocked: prior swing still playing")
		return
	end
	local now = os.clock()
	if now - lastSwingTime < minSwingGap then
		print("[LocalCombatHandler] M1 blocked: swing gap")
		return
	end
	if humanoid:GetAttribute("IsBlocking") then
		print("[LocalCombatHandler] M1 blocked: currently blocking")
		stopPunchTracks("blocking input")
		return
	end
	if humanoid:GetAttribute("IsDodging") then
		print("[LocalCombatHandler] M1 blocked: currently dodging")
		stopPunchTracks("dodging input")
		return
	end

	swinging = true
	print("[LocalCombatHandler] Swinging", currentSwing)

	local track = Punches[currentSwing]
	if not track then
		warn("[LocalCombatHandler] No track for swing", currentSwing)
		swinging = false
		return
	end

	track:Play()
	activeTrack = track

	-- Safety: if blocking is already true (e.g., rapid F+click), stop immediately.
	if humanoid:GetAttribute("IsBlocking") then
		print("[LocalCombatHandler] Force-stopping M1: blocking already active")
		stopPunchTracks("blocking already active")
		return
	end
	if humanoid:GetAttribute("IsDodging") then
		print("[LocalCombatHandler] Force-stopping M1: dodging already active")
		stopPunchTracks("dodging already active")
		return
	end

	track.Stopped:Once(function()
		swinging = false
		activeTrack = nil
		lastSwingTime = os.clock()
		currentSwing += 1
		if currentSwing > #Punches then
			currentSwing = 1
		end
		print("[LocalCombatHandler] Animation finished, next swing:", currentSwing)
	end)
end)

humanoid.AttributeChanged:Connect(function(attr)
	if attr == "IsBlocking" and humanoid:GetAttribute("IsBlocking") then
		print("[LocalCombatHandler] Blocking engaged; stopping punch tracks")
		stopPunchTracks("blocking attribute")
	end
	if attr == "IsDodging" and humanoid:GetAttribute("IsDodging") then
		print("[LocalCombatHandler] Dodging engaged; stopping punch tracks")
		stopPunchTracks("dodging attribute")
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

player.CharacterAdded:Connect(function(char)
	character = char
	humanoid = character:WaitForChild("Humanoid")
	animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	bindTool()
	hookPunchEvents()
end)
