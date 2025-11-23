--[[
LocalCombatHandler (StarterPlayerScripts) - legacy/fallback melee handler.
- Historically: waits for a tool, plays swing animations on M1, drives ClientHitbox, sends CombatEvents.
- Now: acts only as a legacy fallback. It must never run for tools that have their own WeaponClient or are "Fists".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ENABLE_FULL_HANDLER = false -- legacy mode flag; leave false for shipped weapons with their own clients

local function dbg(...)
	print("[LocalCombatHandler][DBG]", ...)
end

dbg("Script started at", script:GetFullName())

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
animator.Parent = humanoid

-- Wait for any Tool (first found in backpack or character)
local tool
repeat
	tool = player.Backpack:FindFirstChildOfClass("Tool") or player.Character:FindFirstChildOfClass("Tool")
	task.wait(0.1)
until tool
dbg("Tool found:", tool.Name, "in", tool.Parent and tool.Parent.Name or "nil")

-- Skip if tool has its own WeaponClient or is explicitly Fists
local hasWeaponClient = tool:FindFirstChild("WeaponClient") ~= nil
if hasWeaponClient or tool.Name == "Fists" then
	dbg(
		"Skipping LocalCombatHandler for tool:",
		tool.Name,
		"hasWeaponClient =",
		hasWeaponClient,
		"reason =",
		hasWeaponClient and "Tool-local WeaponClient present" or "Fists use custom WeaponClient"
	)
	return
end

-- Legacy mode off by default
if not ENABLE_FULL_HANDLER then
	dbg("No WeaponClient on tool", tool.Name, "-- this tool would be handled by LocalCombatHandler if ENABLE_FULL_HANDLER = true.")
	dbg("DEBUG/LEGACY MODE: full handler is disabled (ENABLE_FULL_HANDLER = false). No swings, hitboxes, or block logic will run from LocalCombatHandler.")
	return
end

-- Full legacy handler (unchanged logic below; only runs when ENABLE_FULL_HANDLER == true)

-- Equipped state
local markCombatAction
local equipped = false
tool.Equipped:Connect(function()
	equipped = true
	currentHit = 0
	lastHitTime = 0
	markCombatAction()
	print("[LocalCombatHandler] Tool equipped")
end)
tool.Unequipped:Connect(function()
	equipped = false
	isAttacking = false
	isBlocking = false
	queuedM1 = false
	canQueueNext = false
	inCombat = false
	if blockTrack and blockTrack.IsPlaying then
		blockTrack:Stop(0.1)
	end
	if combatStanceTrack and combatStanceTrack.IsPlaying then
		combatStanceTrack:Stop(0.1)
	end
	BlockEvent:FireServer(false)
	print("[LocalCombatHandler] Tool unequipped")
end)

-- Animations
local sharedAnimations = ReplicatedStorage:WaitForChild("Animations")
local combatStanceTrack = animator:LoadAnimation(sharedAnimations:WaitForChild("CombatStance"))
combatStanceTrack.Priority = Enum.AnimationPriority.Movement
combatStanceTrack.Looped = true

local blockTrack = animator:LoadAnimation(sharedAnimations:WaitForChild("Block"))
blockTrack.Priority = Enum.AnimationPriority.Action
blockTrack.Looped = true

local animFolder = tool:WaitForChild("Animations")
local Config = require(tool:WaitForChild("Config"))

local Punches = {}
for _, animName in ipairs(Config.Combo) do
	-- Don’t treat stance or block anims as combo swings
	if animName ~= "CombatStance" and animName ~= "Block" then
		local anim = sharedAnimations:FindFirstChild(animName) or animFolder:WaitForChild(animName)
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		table.insert(Punches, track)
	end
end


-- Combo state
local currentHit = 0
local isAttacking = false
local queuedM1 = false
local canQueueNext = false
local lastHitTime = 0
local comboResetTime = 0.7
local comboBufferWindow = 0.25
local attackToken = 0

-- Stance state
local inCombat = false
local stanceTimeout = 6
local lastCombatAction = 0
local isBlocking = false
local bufferConn: RBXScriptConnection? = nil

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

local function setCombatStanceEnabled(enabled)
	if not combatStanceTrack then
		return
	end
	if enabled then
		if combatStanceTrack.IsPlaying then
			combatStanceTrack:AdjustWeight(1, 0.05)
		else
			combatStanceTrack:Play(0.1, 1, 1)
		end
	else
		if combatStanceTrack.IsPlaying then
			combatStanceTrack:AdjustWeight(0, 0.05)
		end
	end
end

function markCombatAction()
	lastCombatAction = time()
	if not inCombat then
		inCombat = true
	end
	if not isBlocking and not isAttacking then
		setCombatStanceEnabled(true)
	end
end

RunService.Heartbeat:Connect(function()
	if not inCombat then
		return
	end
	if (time() - lastCombatAction) >= stanceTimeout and not isAttacking and not isBlocking then
		inCombat = false
		isAttacking = false
		queuedM1 = false
		canQueueNext = false
		currentHit = 0
		if combatStanceTrack and combatStanceTrack.IsPlaying then
			combatStanceTrack:Stop(0.1)
		end
	end
end)

local function connectOnce(signal, handler)
	local conn
	conn = signal:Connect(function(...)
		if conn then
			conn:Disconnect()
			conn = nil
		end
		handler(...)
	end)
	return conn
end

local function startBufferWatcher(track)
	if bufferConn then
		bufferConn:Disconnect()
		bufferConn = nil
	end
	canQueueNext = false
	bufferConn = RunService.Heartbeat:Connect(function()
		if not track.IsPlaying then
			bufferConn:Disconnect()
			bufferConn = nil
			return
		end
		local remaining = track.Length - track.TimePosition
		if remaining <= comboBufferWindow then
			canQueueNext = true
			bufferConn:Disconnect()
			bufferConn = nil
		end
	end)
end

local function playPunch(hitIndex)
	local track = Punches[hitIndex]
	if not track then
		warn("[LocalCombatHandler] No track for swing", hitIndex)
		isAttacking = false
		return
	end

	queuedM1 = false
	isAttacking = true
	canQueueNext = false
	markCombatAction()
	setCombatStanceEnabled(false)

	local windupTime = getTimingFromConfig(Config.WindupTime, hitIndex) or 0
	local activeTime = getTimingFromConfig(Config.ActiveTime, hitIndex, Config.ActiveFrames) or 0.1
	local recoveryTime = getTimingFromConfig(Config.RecoveryTime, hitIndex) or Config.M1Recovery or 0.25
	local swingId = hitIndex
	attackToken += 1
	local thisAttack = attackToken

	track:Play()
	startBufferWatcher(track)

	local ok, bufferSignal = pcall(function()
		return track:GetMarkerReachedSignal("Buffer")
	end)
	if ok and bufferSignal then
		bufferSignal:Connect(function()
			canQueueNext = true
		end)
	end

	task.delay(windupTime, function()
		if not track.IsPlaying or not equipped then return end
		hitboxController:StartSwing(swingId, activeTime)
	end)

	task.delay(math.max(track.Length, windupTime + activeTime + recoveryTime) + 0.05, function()
		if thisAttack == attackToken and track.IsPlaying then
			track:Stop()
		end
	end)

	connectOnce(track.Stopped, function()
		if bufferConn then
			bufferConn:Disconnect()
			bufferConn = nil
		end

		if thisAttack ~= attackToken then
			return
		end

		local shouldChain = queuedM1 and hitIndex < #Punches
		if shouldChain then
			currentHit = hitIndex + 1
			queuedM1 = false
			playPunch(currentHit)
			return
		end

		isAttacking = false
		lastHitTime = time()
		queuedM1 = false
		currentHit = hitIndex
		task.delay(recoveryTime, function()
			if not isBlocking and inCombat then
				setCombatStanceEnabled(true)
			end
		end)
	end)

	task.delay(windupTime + activeTime + recoveryTime + 0.1, function()
		if isAttacking and thisAttack == attackToken then
			isAttacking = false
			if not isBlocking and inCombat then
				setCombatStanceEnabled(true)
			end
		end
	end)
end

local function startBlock()
	if isBlocking or not equipped then
		return
	end
	isBlocking = true
	markCombatAction()
	if blockTrack then
		blockTrack:Play(0.05, 1, 1)
	end
	setCombatStanceEnabled(false)
	BlockEvent:FireServer(true)
end

local function endBlock()
	if not isBlocking then
		return
	end
	if blockTrack and blockTrack.IsPlaying then
		blockTrack:Stop(0.1)
	end
	isBlocking = false
	if inCombat and not isAttacking then
		setCombatStanceEnabled(true)
	end
	markCombatAction()
	BlockEvent:FireServer(false)
end

---------------------------------------------------------------------
-- Mouse1 input: plays animation and runs client hitbox window
---------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not equipped then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if isAttacking then
		if canQueueNext then
			queuedM1 = true
		end
		return
	end

	if time() - lastHitTime > comboResetTime or currentHit >= #Punches then
		currentHit = 0
	end
	currentHit = math.clamp(currentHit + 1, 1, #Punches)

	print("[LocalCombatHandler] Swinging", currentHit)
	playPunch(currentHit)
end)

---------------------------------------------------------------------
-- Block input
---------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not equipped then return end
	if input.KeyCode == Enum.KeyCode.F or input.UserInputType == Enum.UserInputType.MouseButton2 then
		startBlock()
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if gp or not equipped then return end
	if input.KeyCode == Enum.KeyCode.F or input.UserInputType == Enum.UserInputType.MouseButton2 then
		endBlock()
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
