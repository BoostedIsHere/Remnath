--[[
Tool-local client for Fists.
- Plays swing animations on M1 and drives client-side Deepwoken-style hitboxes during the active window.
- Fires CombatEvents.M1Event with the tool, swing index, and target humanoid for each new hit.
- Plays HitSound on hitmarker.
- Handles CombatStance idle + block animation in sync with BlockParry attributes.
]]
print("[WeaponClient] FILE VERSION running")

local DEBUG = true
local function dbg(...)
	if DEBUG then
		print("[WeaponClient][DBG]", ...)
	end
end


local tool = script.Parent
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local M1Event        = CombatEvents:WaitForChild("M1Event")
local HitmarkerEvent = CombatEvents:WaitForChild("HitmarkerEvent")

local Config = require(tool:WaitForChild("Config"))
local ClientHitbox = require(ReplicatedStorage.Modules:WaitForChild("ClientHitbox"))

-- Animator
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
    animator = Instance.new("Animator")
    animator.Parent = humanoid
end

-- Animations
local sharedAnimations = ReplicatedStorage:WaitForChild("Animations")
local animFolder = tool:WaitForChild("Animations")

local combatStanceAnim = sharedAnimations:FindFirstChild("CombatStance") or animFolder:FindFirstChild("CombatStance")

local combatStanceTrack = combatStanceAnim and animator:LoadAnimation(combatStanceAnim)
if combatStanceTrack then
    combatStanceTrack.Priority = Enum.AnimationPriority.Action2
    combatStanceTrack.Looped = true
	dbg("Loaded CombatStance animation", combatStanceAnim.AnimationId)
end

local attackTracks = {}
for _, animName in ipairs(Config.Combo) do
    if animName ~= "CombatStance" and animName ~= "Block" then
        local anim = sharedAnimations:FindFirstChild(animName) or animFolder:WaitForChild(animName)
	local track = animator:LoadAnimation(anim)
        track.Priority = Enum.AnimationPriority.Action
        track.Looped = false
        table.insert(attackTracks, track)
    end
end

local attackStoppedConns = {}
local currentSwing = 1
local swinging     = false
local equipped     = false
local isBlocking   = humanoid:GetAttribute("IsBlocking") == true
local lastSwingEnded = 0
local comboResetTime = 0.7
local cancelToolAnimConn: RBXScriptConnection? = nil

local hitSound = tool:FindFirstChild("HitSound")

---------------------------------------------------------------------
-- Hitbox helpers
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
		if not combatStanceTrack.IsPlaying then
			combatStanceTrack:Play(0.1, 1, 1)
			dbg("Playing CombatStance")
		end
	else
		if combatStanceTrack.IsPlaying then
			combatStanceTrack:Stop(0.1)
			dbg("Stopping CombatStance")
		end
	end
end

-- Suppress default Animate tool hold animations so stance can show
local DEFAULT_TOOL_ANIM_IDS = {
	["182393478"] = true, -- ToolNone R6
	["182393474"] = true, -- ToolSlash
	["182393482"] = true, -- ToolLunge
}

local function normalizeAnimId(rawId: string?): string?
	if not rawId or rawId == "" then
		return nil
	end
	return string.match(rawId, "(%d+)")
end

local originalToolAnimIds: { [Animation]: string }? = nil
local function blankDefaultToolAnims()
	local animate = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 2)
	if not animate then
		return
	end

	originalToolAnimIds = originalToolAnimIds or {}
	for _, anim in ipairs(animate:GetDescendants()) do
		if anim:IsA("Animation") then
			local id = normalizeAnimId(anim.AnimationId)
			if id and DEFAULT_TOOL_ANIM_IDS[id] then
				if originalToolAnimIds[anim] == nil then
					originalToolAnimIds[anim] = anim.AnimationId
				end
				anim.AnimationId = ""
				warn("[WeaponClient] Blank default tool anim", anim:GetFullName(), id)
			end
		end
	end
end

local function restoreDefaultToolAnims()
	if not originalToolAnimIds then
		return
	end
	for anim, id in pairs(originalToolAnimIds) do
		if anim and anim.Parent then
			anim.AnimationId = id
		end
	end
	originalToolAnimIds = nil
end

local function stopDefaultToolAnim(track)
	local anim = track.Animation
	if not anim then
		return false
	end
	local id = normalizeAnimId(anim.AnimationId)
	if id and DEFAULT_TOOL_ANIM_IDS[id] then
		track:AdjustWeight(0, 0)
		track:Stop(0.05)
		dbg("Stopped default tool track", anim.Name, anim.AnimationId)
		return true
	end
	return false
end

local function stopDefaultToolTracks()
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if stopDefaultToolAnim(track) then
			track:AdjustWeight(0, 0)
		end
	end
end

local function handleBlockState(blocking)
    isBlocking = blocking
    if blocking then
        currentSwing = 1
        if swinging then
            for _, track in ipairs(attackTracks) do
                if track.IsPlaying then
                    track:Stop(0.05)
                end
            end
            swinging = false
            lastSwingEnded = os.clock()
        end
        setCombatStanceEnabled(false)
    else
        if equipped and not swinging then
            setCombatStanceEnabled(true)
        end
    end
end

humanoid.AttributeChanged:Connect(function(attr)
    if attr == "IsBlocking" then
        handleBlockState(humanoid:GetAttribute("IsBlocking") == true)
    end
end)

---------------------------------------------------------------------
-- Equip / Unequip
---------------------------------------------------------------------
tool.Equipped:Connect(function()
	equipped = true
	swinging = false
	currentSwing = 1
	lastSwingEnded = 0
	if cancelToolAnimConn then
		cancelToolAnimConn:Disconnect()
		cancelToolAnimConn = nil
	end
	cancelToolAnimConn = humanoid.AnimationPlayed:Connect(function(track)
		stopDefaultToolAnim(track)
	end)
	-- Keep default tool anim IDs intact to avoid Animate errors; just stop tracks when they play.
	stopDefaultToolTracks()
	task.spawn(function()
		local deadline = os.clock() + 5
		while os.clock() < deadline and equipped do
			stopDefaultToolTracks()
			task.wait(0.1)
		end
	end)
	if not isBlocking then
		setCombatStanceEnabled(true)
	end
end)

tool.Unequipped:Connect(function()
    equipped = false
    swinging = false
	if cancelToolAnimConn then
		cancelToolAnimConn:Disconnect()
		cancelToolAnimConn = nil
	end
    if combatStanceTrack and combatStanceTrack.IsPlaying then
        combatStanceTrack:Stop(0.1)
    end
end)

---------------------------------------------------------------------
-- M1 input handler
---------------------------------------------------------------------
local function playM1()
    if not equipped then return end
    if swinging then return end
    if isBlocking or humanoid:GetAttribute("IsBlocking") then return end

    local now = os.clock()
    if now - lastSwingEnded > comboResetTime or currentSwing > #attackTracks then
        currentSwing = 1
    end

    local track = attackTracks[currentSwing]
	if not track then
		warn("[WeaponClient] No attack track for swing index", currentSwing)
		return
	end

    local windupTime = getTimingFromConfig(Config.WindupTime, currentSwing) or 0
    local activeTime = getTimingFromConfig(Config.ActiveTime, currentSwing, Config.ActiveFrames) or 0.1
    local recoveryTime = getTimingFromConfig(Config.RecoveryTime, currentSwing) or Config.M1Recovery or 0.25
    local swingId = currentSwing

    if attackStoppedConns[swingId] then
        attackStoppedConns[swingId]:Disconnect()
        attackStoppedConns[swingId] = nil
    end
    if track.IsPlaying then
        track:Stop()
	end

	swinging = true
	setCombatStanceEnabled(false)

	attackStoppedConns[swingId] = track.Stopped:Connect(function()
		swinging = false
		lastSwingEnded = os.clock()
		currentSwing += 1
		if currentSwing > #attackTracks then
			currentSwing = 1
		end
		if not isBlocking and equipped then
			setCombatStanceEnabled(true)
		end
	end)

	track:Play()

    task.delay(windupTime, function()
        if not track.IsPlaying or not equipped then return end
        hitboxController:StartSwing(swingId, activeTime)
    end)

	task.delay(math.max(track.Length, windupTime + activeTime + recoveryTime) + 0.05, function()
		if swinging and not track.IsPlaying then
			swinging = false
			if not isBlocking and equipped then
				setCombatStanceEnabled(true)
			end
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
-- Hitmarker / HitSound
---------------------------------------------------------------------
HitmarkerEvent.OnClientEvent:Connect(function(hitTargetName)
    if not equipped then return end
    if hitSound then
        hitSound:Play()
    end
end)

-- Sync initial block state if we spawned in while blocking
handleBlockState(isBlocking)
