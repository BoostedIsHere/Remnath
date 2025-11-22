-- Server-side block + parry handler. Validates requests, manages state, and exposes helpers for hit resolution.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Config = require(sharedFolder:WaitForChild("Modules"):WaitForChild("BlockParryConfig"))

local BlockParryService = {}
BlockParryService.__index = BlockParryService
local activeServices = {}
local DEBUG_TAG = "[BlockParryServer]"

local function ensureRemotes()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local blockEvent = remotes:FindFirstChild("BlockEvent")
	if not blockEvent then
		blockEvent = Instance.new("RemoteEvent")
		blockEvent.Name = "BlockEvent"
		blockEvent.Parent = remotes
	end

	local parryEvent = remotes:FindFirstChild("ParryEvent")
	if not parryEvent then
		parryEvent = Instance.new("RemoteEvent")
		parryEvent.Name = "ParryEvent"
		parryEvent.Parent = remotes
	end

	return blockEvent, parryEvent
end

local BlockEvent, ParryEvent = ensureRemotes()

local function getSoundTemplate(name)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local soundsFolder = assets:FindFirstChild("Sounds") or assets
		local sound = soundsFolder:FindFirstChild(name)
		if sound and sound:IsA("Sound") then
			return sound
		end
	end

	local ss = game:GetService("SoundService")
	local fallback = ss:FindFirstChild(name)
	if fallback and fallback:IsA("Sound") then
		return fallback
	end

	return nil
end

local function playOneShot(parent, name)
	local template = getSoundTemplate(name)
	if not template or not parent then
		return
	end

	local sound = template:Clone()
	sound.Parent = parent
	sound:Play()
	game:GetService("Debris"):AddItem(sound, sound.TimeLength + 1)
end

function BlockParryService:startBlockLoop()
	if self.blockLoopSound then
		self.blockLoopSound:Destroy()
		self.blockLoopSound = nil
	end

	local template = getSoundTemplate("BlockSound")
	if not template then
		return
	end

	local sound = template:Clone()
	sound.Looped = true
	sound.Parent = self.Character or self.Head or self.Humanoid
	sound:Play()
	self.blockLoopSound = sound
end

function BlockParryService:stopBlockLoop()
	if self.blockLoopSound then
		self.blockLoopSound:Stop()
		self.blockLoopSound:Destroy()
		self.blockLoopSound = nil
	end
end

local function setTimedAttribute(humanoid, attrName, value, duration, tokenMap)
	if not humanoid then
		return
	end

	tokenMap[humanoid] = tokenMap[humanoid] or {}
	local bucket = tokenMap[humanoid]

	bucket[attrName] = (bucket[attrName] or 0) + 1
	local token = bucket[attrName]

	humanoid:SetAttribute(attrName, value)

	task.delay(duration, function()
		local current = tokenMap[humanoid]
		if not current or current[attrName] ~= token then
			return
		end
		humanoid:SetAttribute(attrName, nil)
	end)
end

local function getHumanoidFromAttacker(attacker)
	if not attacker then
		return nil
	end

	if typeof(attacker) == "Instance" then
		if attacker:IsA("Player") then
			local character = attacker.Character
			if character then
				return character:FindFirstChildOfClass("Humanoid")
			end
		end

		if attacker:IsA("Model") then
			return attacker:FindFirstChildOfClass("Humanoid")
		end
	end

	return nil
end

function BlockParryService.new(player)
	local self = setmetatable({}, BlockParryService)

	self.Player = player
	self.Character = nil
	self.Humanoid = nil
	self.Head = nil

	self.toolConns = {}

	self.isBlocking = false
	self.blockHits = 0
	self.blockLoopSound = nil

	self.parryState = "Idle"
	self.parryTimes = nil
	self.parryConn = nil

	self.attributeTokens = {}

	activeServices[player] = self

	player.CharacterAdded:Connect(function(char)
		warn(DEBUG_TAG, "CharacterAdded", player.Name, char and char.Name)
		self:bindCharacter(char)
	end)

	if player.Character then
		self:bindCharacter(player.Character)
	end

	return self
end

function BlockParryService:bindCharacter(character)
	warn(DEBUG_TAG, "Binding character", self.Player.Name, character and character.Name)
	self:stopBlock("CharacterChanged")
	self:finishParry("CharacterChanged")

	self.Character = character
	self.Humanoid = character:FindFirstChildOfClass("Humanoid")
	self.Head = character:FindFirstChild("Head")

	for _, conn in ipairs(self.toolConns) do
		conn:Disconnect()
	end
	self.toolConns = {}

	table.insert(self.toolConns, character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			if self.isBlocking then
				self:stopBlock("Unequipped")
			end
			if self.parryState ~= "Idle" then
				self:finishParry("Unequipped")
			end
		end
	end))

	if self.Humanoid then
		self.Humanoid.Died:Connect(function()
			warn(DEBUG_TAG, "Humanoid died", self.Player.Name)
			self:stopBlock("Died")
			self:finishParry("Died")
		end)
	end
end

function BlockParryService:hasWeaponEquipped()
	if not self.Character then
		return false
	end
	return self.Character:FindFirstChildOfClass("Tool") ~= nil
end

function BlockParryService:setParryState(state)
	self.parryState = state
	if self.Humanoid then
		if state == "Idle" then
			self.Humanoid:SetAttribute("ParryFrame", nil)
			self.Humanoid:SetAttribute("IsParrying", nil)
		else
			self.Humanoid:SetAttribute("ParryFrame", state)
			self.Humanoid:SetAttribute("IsParrying", true)
		end
	end
end

function BlockParryService:startBlock()
	if self.isBlocking then
		return
	end
	if not self.Humanoid or self.Humanoid.Health <= 0 then
		return
	end

	if not self:hasWeaponEquipped() then
		return
	end

	if self.parryState ~= "Idle" then
		return
	end

	if self.Humanoid:GetAttribute("IsDodging") then
		return
	end

	self.isBlocking = true
	self.blockHits = 0

	if self.Humanoid then
		self.Humanoid:SetAttribute("IsBlocking", true)
	end

	self:startBlockLoop()
	warn(DEBUG_TAG, "StartBlock", self.Player.Name)
end

function BlockParryService:stopBlock(_reason)
	if not self.isBlocking then
		return
	end

	self.isBlocking = false
	self.blockHits = 0

	if self.Humanoid then
		self.Humanoid:SetAttribute("IsBlocking", nil)
	end

	self:stopBlockLoop()
	warn(DEBUG_TAG, "StopBlock", self.Player.Name)
end

function BlockParryService:breakBlock(reason)
	self:stopBlock(reason)
	if self.Humanoid then
		setTimedAttribute(self.Humanoid, "Stunned", true, Config.BlockBreakStun, self.attributeTokens)
	end
end

function BlockParryService:registerBlockHit(isHeavy)
	if not self.isBlocking then
		return false
	end

	self.blockHits += 1
	if isHeavy or self.blockHits >= Config.BlockBreakHits then
		self:breakBlock(isHeavy and "Heavy" or "TooManyHits")
		return true
	end

	return false
end

function BlockParryService:startParry()
	if not self.Humanoid or self.Humanoid.Health <= 0 then
		return
	end

	if not self:hasWeaponEquipped() then
		warn(DEBUG_TAG, "StartParry denied, no weapon", self.Player.Name)
		return
	end

	if self.parryState ~= "Idle" then
		return
	end

	if self.isBlocking then
		return
	end

	if self.Humanoid:GetAttribute("IsDodging") then
		return
	end

	self:stopBlock("ParryStart")

	local now = os.clock()
	local perfectWindow = math.min(Config.ParryPerfect, Config.ParryActive)
	self.parryTimes = {
		startupEnd = now + Config.ParryStartup,
		perfectEnd = now + Config.ParryStartup + perfectWindow,
		activeEnd = now + Config.ParryStartup + Config.ParryActive,
		recoveryEnd = now + Config.ParryStartup + Config.ParryActive + Config.ParryRecovery,
	}

	self:setParryState("Startup")
	playOneShot(self.Character or self.Head, "ParrySound")
	warn(DEBUG_TAG, "Parry start", self.Player.Name)

	if self.parryConn then
		self.parryConn:Disconnect()
	end

	self.parryConn = RunService.Heartbeat:Connect(function()
		self:updateParry()
	end)
end

function BlockParryService:updateParry()
	if self.parryState == "Idle" or not self.parryTimes then
		return
	end

	local now = os.clock()
	if now >= self.parryTimes.recoveryEnd then
		self:finishParry("Finished")
		return
	end

	if now < self.parryTimes.startupEnd then
		self:setParryState("Startup")
		return
	end

	if now < self.parryTimes.perfectEnd then
		self:setParryState("Perfect")
		return
	end

	if now < self.parryTimes.activeEnd then
		self:setParryState("Active")
		return
	end

	self:setParryState("Recovery")
end

function BlockParryService:finishParry(_reason)
	self.parryTimes = nil
	self:setParryState("Idle")

	if self.parryConn then
		self.parryConn:Disconnect()
		self.parryConn = nil
	end
end

function BlockParryService:applyParryResult(attacker, perfect)
	local attackerHum = getHumanoidFromAttacker(attacker)
	if attackerHum then
		local stunDuration = perfect and Config.PerfectParryStun or Config.ParryStun
		setTimedAttribute(attackerHum, "Hitstunned", true, stunDuration, self.attributeTokens)
	end

	if self.Humanoid and perfect then
		setTimedAttribute(self.Humanoid, "ParryAdvantage", true, Config.PerfectAdvantage, self.attributeTokens)
	end

	playOneShot(self.Character or self.Head, "ParrySound")

	-- Skip straight to recovery after a parry connect.
	local now = os.clock()
	self.parryTimes = {
		startupEnd = now,
		perfectEnd = now,
		activeEnd = now,
		recoveryEnd = now + Config.ParryRecovery,
	}
	self:setParryState("Recovery")
end

function BlockParryService:HandleBlockRequest(action)
	if action == "Begin" then
		self:startBlock()
	elseif action == "End" then
		self:stopBlock("ClientEnd")
	end
end

function BlockParryService:HandleParryRequest(_timestamp)
	self:startParry()
end

-- Resolve an incoming attack on this defender. Returns a result you can use to drive damage application.
function BlockParryService:ResolveIncomingHit(attacker, attackData)
	local result = {
		damageMultiplier = 1,
		blocked = false,
		parried = false,
		perfect = false,
		blockBroken = false,
	}

	local isHeavy = attackData and attackData.isHeavy

	if self.parryState == "Perfect" then
		result.parried = true
		result.perfect = true
		result.damageMultiplier = 0
		self:applyParryResult(attacker, true)
		warn(DEBUG_TAG, "Perfect parry", self.Player.Name, "against", attacker)
		return result
	end

	if self.parryState == "Active" then
		result.parried = true
		result.damageMultiplier = 0
		self:applyParryResult(attacker, false)
		warn(DEBUG_TAG, "Parry", self.Player.Name, "against", attacker)
		return result
	end

	if self.isBlocking then
		result.blocked = true
		result.damageMultiplier = Config.BlockDamageReduction
		result.blockBroken = self:registerBlockHit(isHeavy)
		warn(DEBUG_TAG, "Blocked hit", self.Player.Name, "heavy", isHeavy, "broken", result.blockBroken)
	end

	return result
end

function BlockParryService.Get(player)
	return activeServices[player]
end

function BlockParryService.GetFromCharacter(character)
	if not character then
		return nil
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player then
		return activeServices[player]
	end

	return nil
end

function BlockParryService.Remove(player)
	activeServices[player] = nil
end

return BlockParryService
