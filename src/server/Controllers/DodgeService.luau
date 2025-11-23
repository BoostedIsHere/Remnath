-- Server-side dodge handler: validates requests, applies movement, controls i-frames, and stops on collision/hitstun.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local DodgeConfig = require(sharedFolder:WaitForChild("Modules"):WaitForChild("DodgeConfig"))

local DodgeService = {}
DodgeService.__index = DodgeService

local function ensureRemotes()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local dodgeEvent = remotes:FindFirstChild("DodgeEvent")
	if not dodgeEvent then
		dodgeEvent = Instance.new("RemoteEvent")
		dodgeEvent.Name = "DodgeEvent"
		dodgeEvent.Parent = remotes
	end

	return dodgeEvent
end

local DodgeEvent = ensureRemotes()

local function horizontal(vec)
	return Vector3.new(vec.X, 0, vec.Z)
end

local function isTruthyAttribute(humanoid, attrName)
	local val = humanoid:GetAttribute(attrName)
	if val == nil then return false end
	if type(val) == "boolean" then
		return val
	end
	if type(val) == "number" then
		return val ~= 0
	end
	return val ~= nil
end

function DodgeService.new(player)
	local self = setmetatable({}, DodgeService)
	self.Player = player
	self.Character = nil
	self.Humanoid = nil
	self.HRP = nil

	self.IsDodging = false
	self.BodyVelocity = nil
	self.IframeActive = false
	self.IframeStartAt = 0
	self.IframeEndsAt = 0
	self.CooldownEndsAt = 0

	self.updateConn = nil
	self.attributeConns = {}

	player.CharacterAdded:Connect(function(char)
		self:bindCharacter(char)
	end)

	if player.Character then
		self:bindCharacter(player.Character)
	end

	return self
end

function DodgeService:bindCharacter(character)
	self:stopDodge("CharacterChanged")

	self.Character = character
	self.Humanoid = character:WaitForChild("Humanoid")
	self.HRP = character:WaitForChild("HumanoidRootPart")

	for _, conn in ipairs(self.attributeConns) do
		conn:Disconnect()
	end
	self.attributeConns = {}

	for _, attr in ipairs(DodgeConfig.InhibitAttributes) do
		table.insert(self.attributeConns, self.Humanoid:GetAttributeChangedSignal(attr):Connect(function()
			if self.IframeActive and isTruthyAttribute(self.Humanoid, attr) then
				self:stripIframes("StatusEffect")
			end
		end))
	end

	self.Humanoid.Died:Connect(function()
		self:stopDodge("Died")
	end)
end

function DodgeService:isInhibited()
	if not self.Humanoid then
		return true
	end

	if self.Humanoid:GetAttribute("IsBlocking") then
		warn("[DodgeService]", self.Player.Name, "dodge denied: blocking")
		return true
	end

	for _, attr in ipairs(DodgeConfig.InhibitAttributes) do
		if isTruthyAttribute(self.Humanoid, attr) then
			return true
		end
	end

	return false
end

function DodgeService:stripIframes(reason)
	if not self.IframeActive then
		return
	end

	self.IframeActive = false
	self.IframeEndsAt = 0
	if self.Humanoid then
		self.Humanoid:SetAttribute("IFrames", nil)
	end
	DodgeEvent:FireClient(self.Player, "IFramesEnd", { reason = reason })
end

function DodgeService:resolveDirection(clientDir)
	local direction = Vector3.new()
	if typeof(clientDir) == "Vector3" then
		direction = clientDir
	end

	if direction.Magnitude < 0.05 and self.Humanoid then
		direction = self.Humanoid.MoveDirection
	end

	if direction.Magnitude < 0.05 and self.HRP then
		direction = self.HRP.CFrame.LookVector
	end

	direction = horizontal(direction)
	if direction.Magnitude > 0 then
		return direction.Unit
	end

	return direction
end

function DodgeService:handleCollision()
	if not self.HRP then
		return
	end

	for _, part in ipairs(self.HRP:GetTouchingParts()) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= self.Character then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			if hum and root and part == root then
				self:stopDodge("Collision")
				return
			end
		end
	end
end

function DodgeService:updateDodge(startTime, duration)
	local now = os.clock()

	if self.IframeActive and (now >= self.IframeEndsAt or self:isInhibited()) then
		self:stripIframes("Expired")
	end

	self:handleCollision()

	if not self.IsDodging then
		return
	end

	if now - startTime >= duration then
		self:stopDodge("Finished")
	end
end

function DodgeService:applyForce(direction, distance, duration)
	if not self.HRP then
		return
	end

	local velocityMagnitude = distance / duration
	local targetVelocity = direction * velocityMagnitude

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 0, 1e5)
	bv.Velocity = Vector3.new(targetVelocity.X, 0, targetVelocity.Z)
	bv.Parent = self.HRP
	Debris:AddItem(bv, duration + 0.1)

	self.BodyVelocity = bv
end

function DodgeService:stopDodge(reason)
	if self.BodyVelocity then
		self.BodyVelocity:Destroy()
		self.BodyVelocity = nil
	end

	if self.updateConn then
		self.updateConn:Disconnect()
		self.updateConn = nil
	end

	self.IsDodging = false
	if self.Humanoid then
		self.Humanoid:SetAttribute("IsDodging", nil)
	end
	self:stripIframes(reason or "End")

	local now = os.clock()
	if reason == "Collision" then
		self.CooldownEndsAt = math.max(self.CooldownEndsAt, now + DodgeConfig.CollisionRecovery)
	end

	DodgeEvent:FireClient(self.Player, "Stop", {
		reason = reason,
		nextAvailable = self.CooldownEndsAt,
	})
end

function DodgeService:HandleDodgeRequest(clientDir, _timestamp)
	if not self.Humanoid or not self.HRP then
		return
	end

	if self.Humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if self.IsDodging or now < self.CooldownEndsAt then
		return
	end

	if self:isInhibited() then
		return
	end

	local direction = self:resolveDirection(clientDir)
	if direction.Magnitude < 0.01 then
		return
	end

	local horizontalSpeed = horizontal(self.HRP.AssemblyLinearVelocity).Magnitude
	local distance = DodgeConfig.BaseDistance + horizontalSpeed * DodgeConfig.MomentumMultiplier
	distance = math.clamp(distance, 0, DodgeConfig.MaxRollDistance)

	local duration = DodgeConfig.RollDuration

	self.IsDodging = true
	if self.Humanoid then
		self.Humanoid:SetAttribute("IsDodging", true)
	end
	self.CooldownEndsAt = now + DodgeConfig.DodgeCooldown
	self.IframeActive = false
	self.IframeStartAt = now + (DodgeConfig.IframeStartOffset or 0)
	self.IframeEndsAt = now + (DodgeConfig.IframeEndOffset or DodgeConfig.IframeDuration)

	self:applyForce(direction, distance, duration)

	local startTime = now
	self.updateConn = RunService.Heartbeat:Connect(function()
		self:updateDodge(startTime, duration)
	end)

	-- Server schedules iframe window; client only mirrors visuals.
	task.delay(math.max(0, self.IframeStartAt - now), function()
		if self.IsDodging and not self:isInhibited() then
			self.IframeActive = true
			if self.Humanoid then
				self.Humanoid:SetAttribute("IFrames", true)
			end
			DodgeEvent:FireClient(self.Player, "IFramesStart", {
				duration = math.max(0, self.IframeEndsAt - self.IframeStartAt),
			})
		end
	end)

	DodgeEvent:FireClient(self.Player, "Start", {
		direction = direction,
		distance = distance,
		duration = duration,
	})
end

return DodgeService
