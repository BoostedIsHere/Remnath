--[[
CombatController (server, per-character)
Current Fists flow:
- Client input (LocalCombatHandler in StarterPlayerScripts + tool-local WeaponClient) plays swing animations and fires CombatEvents.M1Event on the "Hit" marker (payload may include the Tool or just a swing index). Block toggles go through CombatEvents.BlockEvent.
- Server listeners (ServerScriptService scripts and StarterCharacterScripts.CharacterCombat) forward those remotes into the CombatController instance for that character.
- M1Attack pulls per-weapon config via WeaponModule, spawns a temporary hitbox in front of the HumanoidRootPart, applies damage/knockback to nearby humanoids, and signals HitmarkerEvent back to the attacker.
Extension hooks:
- Register new weapons in WeaponModule (sharing their Config) for tuning.
- Religion/divinity systems can wrap these methods to modify damage, block state, or add perk-based effects before/after resolution.
]]
local DEBUG = true  -- flip to false later

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
	self.State = "Idle" -- "Idle", "Attacking", "Blocking", etc.
	return self
end

--// Utility: get current weapon config (or nil)
-- Get current weapon config (if the character is holding a Tool we know).
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

--// Core M1 attack
-- Accepts flexible args so different server scripts still work.
-- Possible calls:
--   controller:M1Attack(player, tool, swingIndex)
--   controller:M1Attack(player, swingIndex)
--   controller:M1Attack(swingIndex)
function CombatController:M1Attack(a, b, c)
	-- Decode args
	local player, tool, swingIndex

	if typeof(a) == "Instance" and a:IsA("Player") then
		player = a
		if typeof(b) == "Instance" and b:IsA("Tool") then
			tool = b
			swingIndex = c
		else
			swingIndex = b
		end
	else
		swingIndex = a
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

	-- Allow attacking from Idle or already Attacking (for chains)
	if self.State ~= "Idle" and self.State ~= "Attacking" then
		return
	end

	self.State = "Attacking"

	-- Get weapon config
	local config
	config, tool = getWeaponConfigForCharacter(character)
	if not config then
		warn("[CombatController] No weapon config for character", character.Name)
		self.State = "Idle"
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		self.State = "Idle"
		return
	end

	-- Read config with fallbacks
	local range          = config.Range or 4
	local hitboxSize     = config.HitboxSize or Vector3.new(4, 4, 4)
	local damageTable    = config.Damage or {}
	local knockTable     = config.Knockback or {}
	local recovery       = config.M1Recovery or 0.25
	local activeFrames   = config.ActiveFrames or {}
	local activeDuration = activeFrames[swingIndex] or activeFrames[1] or 0.1

	local damage    = damageTable[swingIndex] or damageTable[1] or 10
	local knockback = knockTable[swingIndex] or knockTable[1] or 20

	print(("[CombatController] M1Attack swing %d | dmg=%d, kb=%d"):format(swingIndex, damage, knockback))

	----------------------------------------------------------------
	-- Spawn hitbox and keep it aligned to the character's current
	-- facing for the active window. Rotating mid-swing updates the box.
	----------------------------------------------------------------
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox_" .. tostring(swingIndex)
	hitbox.Size = hitboxSize
	hitbox.CanCollide = false
	hitbox.Anchored = true
	hitbox.Transparency = 0.8
	hitbox.Color = Color3.fromRGB(255, 0, 0) -- debug visual
	hitbox.Parent = workspace

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {character}

	local alreadyHit = {} -- prevent multi-hit during this swing
	local startTime = os.clock()

	local function updateHitbox()
		if not character or not character.Parent then
			return false
		end

		local currentHRP = character:FindFirstChild("HumanoidRootPart")
		if not currentHRP then
			return false
		end

		-- Re-align to current facing each frame so turning mid-swing matters.
		local hitboxCFrame = currentHRP.CFrame * CFrame.new(0, 0, -range)
		hitbox.CFrame = hitboxCFrame

		local parts = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)
		for _, part in ipairs(parts) do
			local model = part:FindFirstAncestorOfClass("Model")
			if model and model ~= character then
				local hum = model:FindFirstChildOfClass("Humanoid")
				local targetHRP = model:FindFirstChild("HumanoidRootPart")

				if hum and targetHRP and hum.Health > 0 and not alreadyHit[hum] then
					alreadyHit[hum] = true

					print("[CombatController]  -> Hit", model.Name)
					local damageToApply = damage
					local knockbackScale = 1
					local blockParryResult

					local defenderService = BlockParryService.GetFromCharacter(model)
					if defenderService then
						blockParryResult = defenderService:ResolveIncomingHit(player, {
							isHeavy = config.HeavyAttack == true or config.IsHeavyAttack == true,
						})

						if blockParryResult and blockParryResult.damageMultiplier then
							damageToApply *= blockParryResult.damageMultiplier
						end
					end

					if blockParryResult and blockParryResult.parried then
						-- Defender parried: skip damage/knockback (attacker stun handled by BlockParryService).
						damageToApply = 0
						knockbackScale = 0
					elseif blockParryResult and blockParryResult.blocked then
						-- On block, keep some pushback but soften it.
						knockbackScale = 0.35
					end

					damageToApply = math.max(0, damageToApply)
					if damageToApply > 0 then
						hum:TakeDamage(damageToApply)
					end

					-- Simple knockback
					if knockbackScale > 0 then
						local direction = (targetHRP.Position - currentHRP.Position).Unit
						local bv = Instance.new("BodyVelocity")
						bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
						bv.Velocity = direction * knockback * knockbackScale
						bv.Parent = targetHRP
						Debris:AddItem(bv, 0.2)
					end

					-- Hitmarker to attacker
					if not player then
						player = game.Players:GetPlayerFromCharacter(character)
					end
					if player and (not blockParryResult or not blockParryResult.parried) then
						HitmarkerEvent:FireClient(player, model.Name)
					end
				end
			end
		end

		return true
	end

	-- Align and check immediately, then keep updating through the active window.
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

	Debris:AddItem(hitbox, activeDuration + 0.1)

	----------------------------------------------------------------
	-- Recovery / reset state
	----------------------------------------------------------------
	task.delay(recovery, function()
		if self.State == "Attacking" then
			self.State = "Idle"
		end
	end)
end

--// Blocking
function CombatController:StartBlock()
	self.State = "Blocking"
	print("[CombatController] StartBlock, state now Blocking")
end

function CombatController:EndBlock()
	if self.State == "Blocking" then
		self.State = "Idle"
		print("[CombatController] EndBlock, state now Idle")
	end
end

return CombatController
