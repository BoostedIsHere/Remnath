--[[
CombatController (server, per-character)
- Handles client-predicted hits (client runs Shapecast), server validates range/volume and applies damage/knockback.
- Respects block/parry/dodge via BlockParryService and keeps a legacy fallback volume path for old clients.
]]
local DEBUG = false -- flip to true to add verbose logs

local CombatController = {}
CombatController.__index = CombatController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local HitmarkerEvent = CombatEvents:WaitForChild("HitmarkerEvent")

local WeaponModule = require(ReplicatedStorage.Modules:WaitForChild("WeaponModule"))
local BlockParryService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Controllers"):WaitForChild("BlockParryService"))

--// Constructor
function CombatController.new(character)
	local self = setmetatable({}, CombatController)
	self.Character = character
	self.Humanoid = character:WaitForChild("Humanoid")
	self.State = "Idle"
	self._attackToken = 0
	return self
end

--// Utility
local function getWeaponConfigForCharacter(character)
	if not character then return nil end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then return nil end

	local ok, cfg = pcall(function()
		return WeaponModule.GetWeaponConfig(tool)
	end)

	if not ok then
		warn("[CombatController] WeaponModule.GetWeaponConfig failed:", cfg)
		return nil
	end

	return cfg, tool
end

local function getTimingFromConfig(value, swingIndex, legacyTable, fallback)
	if type(value) == "table" then
		return value[swingIndex] or value[1] or fallback
	end
	if type(value) == "number" then
		return value
	end
	if type(legacyTable) == "table" then
		return legacyTable[swingIndex] or legacyTable[1] or fallback
	end
	return fallback
end

local function applyDamageAndKnockback(attackerPlayer, attackerCharacter, attackerHRP, targetHum, damage, knockback)
	if targetHum.Health <= 0 then
		return
	end

	local targetHRP = targetHum.Parent and targetHum.Parent:FindFirstChild("HumanoidRootPart")
	if not targetHRP then
		return
	end

	if damage > 0 then
		targetHum:TakeDamage(damage)
	end

	if knockback > 0 then
		local displacement = targetHRP.Position - attackerHRP.Position
		local direction = displacement.Magnitude > 0 and displacement.Unit or attackerHRP.CFrame.LookVector
		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		bv.Velocity = direction * knockback
		bv.Parent = targetHRP
		Debris:AddItem(bv, 0.2)
	end

	local attacker = attackerPlayer or Players:GetPlayerFromCharacter(attackerCharacter)
	if attacker and damage > 0 then
		local targetName = targetHum.Parent and targetHum.Parent.Name or targetHum.Name
		HitmarkerEvent:FireClient(attacker, targetName)
	end
end

--// Core M1 attack
function CombatController:M1Attack(a, b, c, d, e)
	-- Decode args
	local player, tool, swingIndex, targetHumanoid, hitPosition

	if typeof(a) == "Instance" and a:IsA("Player") then
		player = a
		if typeof(b) == "Instance" and b:IsA("Tool") then
			tool = b
			if typeof(c) == "Instance" and c:IsA("Humanoid") then
				targetHumanoid = c
			elseif typeof(c) == "Vector3" then
				hitPosition = c
			else
				swingIndex = c
				if typeof(d) == "Instance" and d:IsA("Humanoid") then
					targetHumanoid = d
				elseif typeof(d) == "Vector3" then
					hitPosition = d
				end
			end
		else
			swingIndex = b
			if typeof(c) == "Instance" and c:IsA("Humanoid") then
				targetHumanoid = c
			elseif typeof(c) == "Vector3" then
				hitPosition = c
			end
			if typeof(d) == "Vector3" then
				hitPosition = d
			end
		end
	else
		swingIndex = a
		if typeof(b) == "Instance" and b:IsA("Humanoid") then
			targetHumanoid = b
		elseif typeof(b) == "Vector3" then
			hitPosition = b
		end
		if typeof(c) == "Vector3" then
			hitPosition = c
		end
	end

	if type(swingIndex) ~= "number" then
		swingIndex = 1
	end

	local character = self.Character
	if not character or not self.Humanoid or self.Humanoid.Health <= 0 then
		return
	end

	if self.Humanoid:GetAttribute("IsBlocking") or self.Humanoid:GetAttribute("IsParrying") or self.Humanoid:GetAttribute("IsDodging") then
		return
	end

	if self.State ~= "Idle" and self.State ~= "Attacking" then
		return
	end

	local config
	config, tool = getWeaponConfigForCharacter(character)
	if not config then
		warn("[CombatController] No weapon config for character", character.Name)
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local range         = config.Range or 4
	local hitboxSize    = config.HitboxSize or Vector3.new(4, 4, 4)
	local hitboxOffset  = config.HitboxOffset or CFrame.new(0, 0, -range)
	local castType      = config.CastType or "Blockcast"
	local hitboxRadius  = config.HitboxRadius or 0
	local damageTable   = config.Damage or {}
	local knockTable    = config.Knockback or {}
	local activeFrames  = config.ActiveFrames or {}

	local damage          = damageTable[swingIndex] or damageTable[1] or 10
	local knockback       = knockTable[swingIndex] or knockTable[1] or 20
	local activeDuration  = getTimingFromConfig(config.ActiveTime, swingIndex, activeFrames, 0.1)
	local recovery        = getTimingFromConfig(config.RecoveryTime, swingIndex, nil, config.M1Recovery or 0.25)
	local validationScale = config.ServerValidationScale or 0.85
	local isHeavy         = config.HeavyAttack == true or config.IsHeavyAttack == true

	self.State = "Attacking"
	local attackToken = os.clock()
	self._attackToken = attackToken

	task.delay(recovery, function()
		if self.State == "Attacking" and self._attackToken == attackToken then
			self.State = "Idle"
		end
	end)

	-- Client-provided target path
	if typeof(targetHumanoid) == "Instance" and targetHumanoid:IsA("Humanoid") then
		local targetCharacter = targetHumanoid.Parent
		local targetHRP = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")

		if not targetCharacter or not targetHRP or targetHumanoid.Health <= 0 then return end
		if targetCharacter == character then return end

		local allowedDistance = range + ((hitboxSize.Z) * 0.5) + hitboxRadius
		if (targetHRP.Position - hrp.Position).Magnitude > allowedDistance then return end

		if hitPosition then
			local posDistance = (hitPosition - hrp.Position).Magnitude
			if posDistance > allowedDistance + 1 then return end
		end

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = {character}

		local withinVolume = false
		if castType == "Spherecast" then
			local sphereRadius = (hitboxRadius > 0 and hitboxRadius or (hitboxSize.Magnitude * 0.25)) * validationScale
			local center = (hrp.CFrame * hitboxOffset).Position
			if (targetHRP.Position - center).Magnitude <= sphereRadius then
				withinVolume = true
			end
		else
			local validationSize = hitboxSize * validationScale
			local validationCFrame = hrp.CFrame * hitboxOffset
			for _, part in ipairs(workspace:GetPartBoundsInBox(validationCFrame, validationSize, overlapParams)) do
				if part:IsDescendantOf(targetCharacter) then
					withinVolume = true
					break
				end
			end
		end

		if not withinVolume then return end

		local damageToApply = damage
		local knockbackScale = 1
		local defenderService = BlockParryService.GetFromCharacter(targetCharacter)
		if defenderService then
			local blockParryResult = defenderService:ResolveIncomingHit(player, { isHeavy = isHeavy })
			if blockParryResult and blockParryResult.damageMultiplier then
				damageToApply *= blockParryResult.damageMultiplier
			end
			if blockParryResult and blockParryResult.parried then
				damageToApply = 0
				knockbackScale = 0
			elseif blockParryResult and blockParryResult.blocked then
				knockbackScale = 0.35
			end
		end

		damageToApply = math.max(0, damageToApply)
		if damageToApply > 0 or knockbackScale > 0 then
			applyDamageAndKnockback(player, character, hrp, targetHumanoid, damageToApply, knockback * knockbackScale)
		end
		return
	end

	-- Fallback server-driven volume (legacy clients)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {character}

	local alreadyHit = {}
	local startTime = os.clock()

	local function updateHitbox()
		if not character or not character.Parent then return false end
		local currentHRP = character:FindFirstChild("HumanoidRootPart")
		if not currentHRP then return false end

		local hitboxCFrame = currentHRP.CFrame * hitboxOffset
		local parts
		if castType == "Spherecast" then
			parts = workspace:GetPartBoundsInRadius(hitboxCFrame.Position, (hitboxRadius > 0 and hitboxRadius or (hitboxSize.Magnitude * 0.25)), overlapParams)
		else
			parts = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)
		end

		for _, part in ipairs(parts) do
			local model = part:FindFirstAncestorOfClass("Model")
			if model and model ~= character then
				local hum = model:FindFirstChildOfClass("Humanoid")
				local targetHRP = model:FindFirstChild("HumanoidRootPart")

				if hum and targetHRP and hum.Health > 0 and not alreadyHit[hum] then
					alreadyHit[hum] = true
					if DEBUG then
						print("[CombatController]  -> Hit", model.Name)
					end

					local damageToApply = damage
					local knockbackScale = 1
					local defenderService = BlockParryService.GetFromCharacter(model)
					if defenderService then
						local blockParryResult = defenderService:ResolveIncomingHit(player, { isHeavy = isHeavy })
						if blockParryResult and blockParryResult.damageMultiplier then
							damageToApply *= blockParryResult.damageMultiplier
						end
						if blockParryResult and blockParryResult.parried then
							damageToApply = 0
							knockbackScale = 0
						elseif blockParryResult and blockParryResult.blocked then
							knockbackScale = 0.35
						end
					end

					damageToApply = math.max(0, damageToApply)
					if damageToApply > 0 or knockbackScale > 0 then
						applyDamageAndKnockback(player, character, currentHRP, hum, damageToApply, knockback * knockbackScale)
					end
				end
			end
		end

		return true
	end

	updateHitbox()
	local hbConn
	hbConn = RunService.Heartbeat:Connect(function()
		if os.clock() - startTime >= activeDuration then
			hbConn:Disconnect()
			return
		end
		if not updateHitbox() then
			hbConn:Disconnect()
		end
	end)
end

--// Blocking
function CombatController:StartBlock()
	self.State = "Blocking"
	if DEBUG then
		print("[CombatController] StartBlock, state now Blocking")
	end
end

function CombatController:EndBlock()
	if self.State == "Blocking" then
		self.State = "Idle"
		if DEBUG then
			print("[CombatController] EndBlock, state now Idle")
		end
	end
end

return CombatController
