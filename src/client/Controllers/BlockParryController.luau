-- Client-side handler for block/parry input. Hold RMB/F to block, tap to parry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local BlockParryConfig = require(sharedFolder:WaitForChild("Modules"):WaitForChild("BlockParryConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local BlockEvent = remotes:WaitForChild("BlockEvent")
local ParryEvent = remotes:WaitForChild("ParryEvent")
local Animations = ReplicatedStorage:WaitForChild("Animations")

local function getSoundTemplate(name)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local sounds = assets:FindFirstChild("Sounds") or assets
		local sound = sounds:FindFirstChild(name)
		if sound and sound:IsA("Sound") then
			return sound
		end
	end

	local soundService = game:GetService("SoundService")
	local fallback = soundService:FindFirstChild(name)
	if fallback and fallback:IsA("Sound") then
		return fallback
	end

	return nil
end

local function playOneShot(name, parent)
	local template = getSoundTemplate(name)
	if not template then
		return
	end

	local clone = template:Clone()
	clone.Parent = parent or workspace
	clone:Play()
	game:GetService("Debris"):AddItem(clone, clone.TimeLength + 1)
end

local BlockParryController = {}
BlockParryController.__index = BlockParryController

local HOLD_THRESHOLD = 0.2 -- seconds to differentiate between tap (parry) and hold (block)

local function relevantInput(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		return true, "MouseButton2"
	end

	if input.KeyCode == Enum.KeyCode.F then
		return true, "F"
	end

	return false, nil
end

function BlockParryController.new()
	local self = setmetatable({}, BlockParryController)

	self.Player = Players.LocalPlayer
	self.Humanoid = nil
	self.Character = nil
	self.toolConns = {}
	self.attrConns = {}
	self.Animator = nil
	self.blockTrack = nil

	self.activeInputs = {}
	self.isBlocking = false
	self.parryLockUntil = 0
	self.blockStartedAt = 0
	self.debugTag = "[BlockParryClient]"
	self.blockLoop = nil

	self.characterAddedConn = self.Player.CharacterAdded:Connect(function(char)
		self:bindCharacter(char)
	end)

	if self.Player.Character then
		self:bindCharacter(self.Player.Character)
	end

	self.inputBeganConn = UserInputService.InputBegan:Connect(function(input, gp)
		self:onInputBegan(input, gp)
	end)

	self.inputEndedConn = UserInputService.InputEnded:Connect(function(input, gp)
		self:onInputEnded(input, gp)
	end)

	return self
end

function BlockParryController:bindCharacter(character)
	self.Character = character
	self.Humanoid = character:FindFirstChildOfClass("Humanoid")
	self.Animator = nil

	for _, conn in ipairs(self.toolConns) do
		conn:Disconnect()
	end
	self.toolConns = {}

	for _, conn in ipairs(self.attrConns) do
		conn:Disconnect()
	end
	self.attrConns = {}

	table.insert(self.toolConns, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			warn(self.debugTag, "Tool equipped:", child.Name)
		end
	end))

	table.insert(self.toolConns, character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and self.isBlocking then
			self:stopBlock()
		end
	end))

	if self.Humanoid then
		self.Animator = self.Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		self.Animator.Parent = self.Humanoid

		local blockAnim = Animations:FindFirstChild("Block")
		if blockAnim then
			self.blockTrack = self.Animator:LoadAnimation(blockAnim)
			self.blockTrack.Priority = Enum.AnimationPriority.Action
			self.blockTrack.Looped = true
		end
	end

	if self.Humanoid then
		table.insert(self.attrConns, self.Humanoid.AttributeChanged:Connect(function(attr)
			if attr == "IsBlocking" then
				local nowBlocking = self.Humanoid:GetAttribute("IsBlocking")
				if nowBlocking then
					self.isBlocking = true
					if self.blockTrack and not self.blockTrack.IsPlaying then
						self.blockTrack:Play(0.05, 1, 1)
					end
				else
					if self.blockTrack and self.blockTrack.IsPlaying then
						self.blockTrack:Stop(0.1)
					end
					if self.blockLoop then
						self.blockLoop:Stop()
						self.blockLoop:Destroy()
						self.blockLoop = nil
					end
					self.isBlocking = false
				end
			end
		end))
	end
end

function BlockParryController:isAlive()
	if not self.Humanoid then
		return true
	end

	return self.Humanoid.Health > 0
end

function BlockParryController:isBusy()
	if not self.Humanoid then
		return false
	end

	return self.Humanoid:GetAttribute("IsBlocking")
		or self.Humanoid:GetAttribute("IsParrying")
		or self.Humanoid:GetAttribute("IsDodging")
end

function BlockParryController:hasWeaponEquipped()
	if not self.Character then
		return false
	end

	return self.Character:FindFirstChildOfClass("Tool") ~= nil
end

function BlockParryController:startBlock()
	if self.isBlocking then
		return
	end

	if not self:isAlive() or not self:hasWeaponEquipped() then
		warn(self.debugTag, "StartBlock denied", "alive", self:isAlive(), "weapon", self:hasWeaponEquipped())
		return
	end

	if self:isBusy() then
		warn(self.debugTag, "StartBlock denied: busy state")
		return
	end

	self.isBlocking = true
	self.blockStartedAt = os.clock()
	warn(self.debugTag, "StartBlock -> firing Begin")
	if self.Humanoid then
		self.Humanoid:SetAttribute("IsBlocking", true)
	end
	if self.blockTrack then
		self.blockTrack:Play(0.05, 1, 1)
	end
	BlockEvent:FireServer("Begin")

	local template = getSoundTemplate("BlockSound")
	if template then
		if self.blockLoop then
			self.blockLoop:Stop()
			self.blockLoop:Destroy()
			self.blockLoop = nil
		end

		local sound = template:Clone()
		sound.Looped = true
		sound.Parent = self.Character or self.Player.Character or self.Player
		sound:Play()
		self.blockLoop = sound
	end
end

function BlockParryController:stopBlock()
	if not self.isBlocking then
		return
	end

	self.isBlocking = false
	warn(self.debugTag, "StopBlock -> firing End")
	if self.Humanoid then
		self.Humanoid:SetAttribute("IsBlocking", false)
	end
	BlockEvent:FireServer("End")

	if self.blockTrack and self.blockTrack.IsPlaying then
		self.blockTrack:Stop(0.1)
	end

	if self.blockLoop then
		self.blockLoop:Stop()
		self.blockLoop:Destroy()
		self.blockLoop = nil
	end
end

function BlockParryController:attemptParry()
	local now = os.clock()
	if now < self.parryLockUntil then
		warn(self.debugTag, "Parry denied: locked until", self.parryLockUntil, "now", now)
		return
	end

	if not self:isAlive() then
		warn(self.debugTag, "Parry denied: not alive")
		return
	end

	if self:isBusy() then
		warn(self.debugTag, "Parry denied: busy state")
		return
	end

	if not self:hasWeaponEquipped() then
		warn(self.debugTag, "Parry denied: no weapon equipped")
		return
	end

	self.parryLockUntil = now + BlockParryConfig.ParryStartup + BlockParryConfig.ParryActive + BlockParryConfig.ParryRecovery

	if self.isBlocking then
		self:stopBlock()
	end

	warn(self.debugTag, "Parry -> firing request", now)
	playOneShot("ParrySound", self.Character or self.Player.Character or self.Player)
	ParryEvent:FireServer(now)
end

function BlockParryController:onInputBegan(input, gameProcessed)
	if gameProcessed then
		return
	end

	local ok, key = relevantInput(input)
	if not ok then
		return
	end

	local now = os.clock()
	self.activeInputs[key] = now
	warn(self.debugTag, "InputBegan", key, "at", now, "hasWeapon", self:hasWeaponEquipped())

	task.delay(HOLD_THRESHOLD, function()
		if self.activeInputs[key] and not self.isBlocking then
			self:startBlock()
		end
	end)
end

function BlockParryController:onInputEnded(input, gameProcessed)
	if gameProcessed then
		return
	end

	local ok, key = relevantInput(input)
	if not ok then
		return
	end

	local beganAt = self.activeInputs[key]
	self.activeInputs[key] = nil

	if self.isBlocking then
		warn(self.debugTag, "InputEnded stopping block", key)
		self:stopBlock()
		return
	end

	if not beganAt then
		return
	end

	local duration = os.clock() - beganAt
	warn(self.debugTag, "InputEnded", key, "duration", duration)
	if duration <= HOLD_THRESHOLD + 0.05 then
		self:attemptParry()
	end
end

function BlockParryController:Destroy()
	if self.inputBeganConn then
		self.inputBeganConn:Disconnect()
		self.inputBeganConn = nil
	end
	if self.inputEndedConn then
		self.inputEndedConn:Disconnect()
		self.inputEndedConn = nil
	end
	if self.characterAddedConn then
		self.characterAddedConn:Disconnect()
		self.characterAddedConn = nil
	end

	self.activeInputs = {}
	if self.isBlocking then
		self:stopBlock()
	end

	for _, conn in ipairs(self.toolConns) do
		conn:Disconnect()
	end
	self.toolConns = {}

	for _, conn in ipairs(self.attrConns) do
		conn:Disconnect()
	end
	self.attrConns = {}

	if self.blockLoop then
		self.blockLoop:Stop()
		self.blockLoop:Destroy()
		self.blockLoop = nil
	end
	if self.blockTrack then
		self.blockTrack:Stop()
		self.blockTrack = nil
	end
end

return BlockParryController
