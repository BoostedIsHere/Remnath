--!strict
-- Shared client wrapper around ShapecastHitbox for melee weapons.
-- Builds one persistent hitbox per tool and exposes StartSwing to run a timed window with per-swing targetsHit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShapecastHitbox = require(ReplicatedStorage.Modules:WaitForChild("ShapecastHitBox"))

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

function ClientHitbox.new(params: Params): HitboxController
	local tool = params.Tool
	local character = params.Character
	local config = params.Config
	local onHit = params.OnHit
	local onFallback = params.OnFallback

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {character}
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
		if not handle then
			warn("[ClientHitbox] No Handle found on tool", tool.Name)
			return nil
		end

		local ok, hb = pcall(function()
			return ShapecastHitbox.new(handle, raycastParams)
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

		-- read cast data from config
		local castType = mapCastType(config.CastType)
		local hitboxSize = config.HitboxSize or Vector3.new(2, 2, 2)
		local hitboxOffset = config.HitboxOffset or CFrame.new()
		local hitboxRadius = config.HitboxRadius or 0

		local targetsHit: {[Humanoid]: boolean} = {}

		hb:SetCastData({
			CastType = castType,
			Size = hitboxSize,
			CFrame = hitboxOffset,
			Radius = hitboxRadius,
		})

		hb:BeforeStart(function()
			targetsHit = {}
			raycastParams.FilterDescendantsInstances = {character}
			hb.RaycastParams = raycastParams
		end)

		hb:OnUpdate(function()
			if not hb.Active then
				return
			end

			-- Attachments already follow the fist; keep casts centered on each segment with optional local offset.
			for _, segment in hb:GetAllSegments() do
				segment.CastData.CastType = castType
				segment.CastData.Size = hitboxSize
				segment.CastData.Radius = hitboxRadius
				segment.CastData.CFrame = hitboxOffset
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
		end)

		hb:HitStart(activeTime)
	end

	function controller:Destroy()
		if hitbox then
			hitbox:Destroy()
		end
	end

	return controller
end

return ClientHitbox
