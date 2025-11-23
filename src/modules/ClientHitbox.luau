--!strict
-- Shared client wrapper around ShapecastHitbox for melee weapons.
-- Builds one persistent hitbox per tool and exposes StartSwing to run a timed window with per-swing targetsHit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ShapecastHitbox = require(ReplicatedStorage.Modules:WaitForChild("ShapecastHitBox"))

-- We'll handle debug visuals ourselves; hide built-in Shapecast debug trails
if ShapecastHitbox.Settings then
	ShapecastHitbox.Settings.Debug_Visible = false
end

export type HitCallback = (humanoid: Humanoid, hitPosition: Vector3?, swingIndex: number) -> ()
export type FallbackCallback = (swingIndex: number) -> ()

export type HitboxController = {
	StartSwing: (self: HitboxController, swingIndex: number, activeTime: number) -> (),
	Destroy: (self: HitboxController) -> (),
}

type Params = {
	Tool: Tool,
	Character: Model,
	Config: any,
	OnHit: HitCallback,
	OnFallback: FallbackCallback,
}

local ClientHitbox = {}

local DEBUG_MELEE_HITBOX = true
local debugParts: { [Attachment]: Part } = {}

function ClientHitbox.new(params: Params): HitboxController
	local tool = params.Tool
	local character = params.Character
	local config = params.Config
	local onHit = params.OnHit
	local onFallback = params.OnFallback

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = true

	local hitbox: any? = nil

	local function mapCastType(value: string?)
		if value == ShapecastHitbox.CastTypes.Spherecast or value == "Spherecast" then
			return ShapecastHitbox.CastTypes.Spherecast
		end
		if value == ShapecastHitbox.CastTypes.Blockcast or value == "Blockcast" then
			return ShapecastHitbox.CastTypes.Blockcast
		end
		if value == ShapecastHitbox.CastTypes.Raycast or value == "Raycast" then
			return ShapecastHitbox.CastTypes.Raycast
		end
		return ShapecastHitbox.CastTypes.Blockcast
	end

	local function ensureHitbox(): any?
		if hitbox then
			return hitbox
		end

		local handle = tool:FindFirstChild("Handle")
		local rootInstance: Instance? = handle
		if config.CastRoot == "Character" then
			rootInstance = character
		end

		if not rootInstance then
			warn("[ClientHitbox] No root instance for hitbox (Handle/Character missing) on tool", tool.Name)
			return nil
		end

		local ok, hb = pcall(function()
			return ShapecastHitbox.new(rootInstance, raycastParams)
		end)

		if not ok or not hb then
			warn("[ClientHitbox] Failed to construct ShapecastHitbox:", hb)
			return nil
		end

		hitbox = hb
		return hitbox
	end

	local controller: HitboxController = {} :: HitboxController

	function controller:StartSwing(swingIndex: number, activeTime: number)
		local hb = ensureHitbox()
		if not hb then
			if onFallback then
				onFallback(swingIndex)
			end
			return
		end

		-- read cast data from config (exact values, no scaling)
		local castType = mapCastType(config.CastType)
		local hitboxSize = config.HitboxSize or Vector3.new(2, 2, 2)
		local hitboxOffset = config.HitboxOffset or CFrame.new()
		local hitboxRadius = config.HitboxRadius or 0

		local targetsHit: { [Humanoid]: boolean } = {}

		hb:SetCastData({
			CastType = castType,
			Size = hitboxSize,
			CFrame = hitboxOffset,
			Radius = hitboxRadius,
		})

		hb:BeforeStart(function()
			targetsHit = {}
			raycastParams.FilterDescendantsInstances = { character }
			hb.RaycastParams = raycastParams
		end)

		hb:OnUpdate(function()
			if not hb.Active then
				return
			end

			for attachment, segment in pairs(hb:GetAllSegments()) do
				if not attachment or not segment then
					continue
				end
				local castData = segment.CastData
				if not castData then
					continue
				end

				castData.CastType = castType
				castData.Size = hitboxSize
				castData.Radius = hitboxRadius
				castData.CFrame = hitboxOffset

				if DEBUG_MELEE_HITBOX then
					local dbg = debugParts[attachment]
					if not dbg then
						dbg = Instance.new("Part")
						dbg.Name = (tool and tool.Name or "Weapon") .. "_HitboxDebug"
						dbg.Anchored = true
						dbg.CanCollide = false
						dbg.CanQuery = false
						dbg.CanTouch = false
						dbg.Material = Enum.Material.Neon
						dbg.Transparency = 0.5
						dbg.Parent = Workspace
						debugParts[attachment] = dbg
					end

					local worldCF = attachment.WorldCFrame * castData.CFrame

					if castType == ShapecastHitbox.CastTypes.Blockcast then
						dbg.Size = castData.Size
						dbg.CFrame = worldCF
					elseif castType == ShapecastHitbox.CastTypes.Spherecast then
						local r = castData.Radius
						dbg.Size = Vector3.new(r * 2, r * 2, r * 2)
						dbg.CFrame = worldCF
					else
						dbg.Size = Vector3.new(0.2, 0.2, 0.2)
						dbg.CFrame = worldCF
					end
				end
			end

			if DEBUG_MELEE_HITBOX then
				for attachment, part in pairs(debugParts) do
					if not attachment or not hb:GetSegment(attachment) then
						part:Destroy()
						debugParts[attachment] = nil
					end
				end
			end
		end)

		hb:OnHit(function(result)
			local model = result.Instance and result.Instance:FindFirstAncestorOfClass("Model")
			if not model or model == character then
				return
			end

			local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
			if hum and hum.Health > 0 and not targetsHit[hum] then
				targetsHit[hum] = true
				if onHit then
					onHit(hum, result.Position, swingIndex)
				end
			end
		end)

		hb:OnStopped(function(cleanCallbacks)
			cleanCallbacks()
			if DEBUG_MELEE_HITBOX then
				for _, part in pairs(debugParts) do
					part:Destroy()
				end
				table.clear(debugParts)
			end
		end)

		hb:HitStart(activeTime)
	end

	function controller:Destroy()
		if hitbox then
			hitbox:Destroy()
		end
		if DEBUG_MELEE_HITBOX then
			for _, part in pairs(debugParts) do
				part:Destroy()
			end
			table.clear(debugParts)
		end
	end

	return controller
end

return ClientHitbox
