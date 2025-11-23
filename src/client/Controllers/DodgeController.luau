-- Client-side dodge controller: collects input, sends requests, and mirrors server start/stop signals.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local DodgeConfig = require(sharedFolder:WaitForChild("Modules"):WaitForChild("DodgeConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local DodgeEvent = remotes:WaitForChild("DodgeEvent")

local DodgeController = {}
DodgeController.__index = DodgeController

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

function DodgeController.new(movementInput)
	local self = setmetatable({}, DodgeController)

	self.Player = Players.LocalPlayer
	self.MovementInput = movementInput

	self.Character = nil
	self.Humanoid = nil
	self.HRP = nil
	self.Animator = nil
	self.RollTrack = nil

	self.localCooldownEnds = 0
	self.predictedRollEnd = 0
	self.iframeEnd = 0
	self.iframeConn = nil
	self.iframeHighlight = nil

	self.CharacterAddedConn = self.Player.CharacterAdded:Connect(function(char)
		self:bindCharacter(char)
	end)

	if self.Player.Character then
		self:bindCharacter(self.Player.Character)
	else
		self.Player.CharacterAdded:Wait()
	end

	if self.MovementInput then
		self.MovementInput:GetSignal():Connect(function(direction)
			self:requestDodge(direction)
		end)
	end

	DodgeEvent.OnClientEvent:Connect(function(action, payload)
		self:handleRemote(action, payload)
	end)

	RunService.RenderStepped:Connect(function()
		self:updatePrediction()
	end)

	return self
end

function DodgeController:bindCharacter(character)
	self.Character = character
	self.Humanoid = character:WaitForChild("Humanoid")
	self.HRP = character:WaitForChild("HumanoidRootPart")
	self.Animator = self.Humanoid:FindFirstChildOfClass("Animator")
	if not self.Animator then
		self.Animator = Instance.new("Animator")
		self.Animator.Parent = self.Humanoid
	end

	self.RollTrack = nil
	local animFolder = ReplicatedStorage:FindFirstChild("Animations") or ReplicatedStorage:FindFirstChild("AllAnimations")
	if animFolder then
		local rollAnim = animFolder:FindFirstChild("BaseForwardDodge")
		if rollAnim then
			local track = self.Animator:LoadAnimation(rollAnim)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			self.RollTrack = track
		end
	end

	if self.MovementInput then
		self.MovementInput:BindCharacter(character)
	end

	-- Clean up any lingering VFX on respawn
	if self.iframeConn then
		self.iframeConn:Disconnect()
		self.iframeConn = nil
	end
	if self.iframeHighlight then
		self.iframeHighlight:Destroy()
		self.iframeHighlight = nil
	end
end

local function horizontal(vec)
	return Vector3.new(vec.X, 0, vec.Z)
end

function DodgeController:computeDirection(direction)
	local dir = direction or Vector3.new()

	if dir.Magnitude < 0.05 and self.Humanoid then
		dir = self.Humanoid.MoveDirection
	end

	if dir.Magnitude < 0.05 and self.HRP then
		dir = self.HRP.CFrame.LookVector
	end

	dir = horizontal(dir)
	if dir.Magnitude == 0 then
		return dir
	end

	return dir.Unit
end

function DodgeController:requestDodge(direction)
	local now = os.clock()
	if now < self.localCooldownEnds then
		return
	end

	if not self.Humanoid or self.Humanoid.Health <= 0 then
		return
	end

	if self.Humanoid:GetAttribute("IsBlocking") then
		print("[DodgeController] Dodge blocked: currently blocking")
		return
	end

	local dir = self:computeDirection(direction)
	if dir.Magnitude == 0 then
		return
	end

	self.localCooldownEnds = now + DodgeConfig.DodgeCooldown
	self.predictedRollEnd = now + DodgeConfig.RollDuration
	self.iframeEnd = now + DodgeConfig.IframeDuration

	DodgeEvent:FireServer(dir, now)
end

function DodgeController:handleRemote(action, payload)
	payload = payload or {}
	local now = os.clock()

	if action == "Start" then
		self.predictedRollEnd = now + (payload.duration or DodgeConfig.RollDuration)
		self.localCooldownEnds = now + DodgeConfig.DodgeCooldown
		if payload.iframes and payload.iframes > 0 then
			self.iframeEnd = now + payload.iframes
		else
			self.iframeEnd = now
		end

	if self.RollTrack then
			self.RollTrack:Stop(0)
			self.RollTrack:Play()
		end
		return
	end

	if action == "IFramesStart" then
		local duration = payload.duration or DodgeConfig.IframeDuration
		self.iframeEnd = now + duration

		if self.iframeHighlight then
			self.iframeHighlight:Destroy()
			self.iframeHighlight = nil
		end

		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 0.3
		highlight.OutlineColor = Color3.fromRGB(80, 160, 255) -- blue shimmer for iframes
		highlight.Adornee = self.Character
		highlight.Parent = self.Character
		self.iframeHighlight = highlight

		if self.iframeConn then
			self.iframeConn:Disconnect()
		end
		local started = os.clock()
		self.iframeConn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - started
			local pulse = 0.15 + 0.15 * math.sin(t * 20)
			highlight.OutlineTransparency = math.clamp(0.2 + pulse, 0, 1)
		end)

		local soundTemplate = getSoundTemplate("DodgeIFrameSound") or getSoundTemplate("ParrySound")
		if soundTemplate then
			local s = soundTemplate:Clone()
			s.Volume = 0.5
			s.Parent = self.Character or self.Humanoid or workspace
			s:Play()
			game:GetService("Debris"):AddItem(s, s.TimeLength + 0.5)
		end

		return
	end

	if action == "Stop" then
		self.predictedRollEnd = now
		if payload.nextAvailable then
			self.localCooldownEnds = math.max(self.localCooldownEnds, payload.nextAvailable)
		end
		if self.iframeConn then
			self.iframeConn:Disconnect()
			self.iframeConn = nil
		end
		if self.iframeHighlight then
			self.iframeHighlight:Destroy()
			self.iframeHighlight = nil
		end
		return
	end

	if action == "IFramesEnd" then
		self.iframeEnd = now
		if self.iframeConn then
			self.iframeConn:Disconnect()
			self.iframeConn = nil
		end
		if self.iframeHighlight then
			self.iframeHighlight:Destroy()
			self.iframeHighlight = nil
		end
	end
end

function DodgeController:updatePrediction()
	local now = os.clock()
	if now >= self.predictedRollEnd then
		-- Stop any predicted visuals here once animations are wired.
	end
end

return DodgeController
