-- Minimal BlockParryService to support block/parry/dodge gating.
-- Used in two ways:
--   1) BlockParryService.GetFromCharacter(character) -> resolver:ResolveIncomingHit(...)
--   2) BlockParryService.new(player) -> per-player service with HandleBlockRequest / HandleParryRequest

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockParryService = {}
local BlockParryConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("BlockParryConfig"))

-- Per-character resolvers for incoming hits
local characterRegistry: { [Model]: any } = {}

--// Internal: builds a resolver bound to a specific character
local function newResolver(character: Model)
	local resolver = {}
	resolver.Character = character

	function resolver:ResolveIncomingHit(attacker: Player?, params)
		local hum = character:FindFirstChildOfClass("Humanoid")
		local result = {}
		local damageMultiplier = 1

		if hum then
			-- Parry fully nullifies damage
			if hum:GetAttribute("IsParrying") then
				result.parried = true
				damageMultiplier = 0
			-- Block partially reduces damage
			elseif hum:GetAttribute("IsBlocking") then
				result.blocked = true
				damageMultiplier = hum:GetAttribute("BlockDamageMultiplier") or 0.5
			end

			-- Dodge = treat as full avoid as well
			if hum:GetAttribute("IsDodging") then
				result.parried = true
				damageMultiplier = 0
			end
		end

		result.damageMultiplier = damageMultiplier
		return result
	end

	return resolver
end

--// Public: used by CombatController to resolve whether a hit is blocked/parried/dodged
function BlockParryService.GetFromCharacter(character: Model)
	if not character then
		return nil
	end

	if characterRegistry[character] then
		return characterRegistry[character]
	end

	local resolver = newResolver(character)
	characterRegistry[character] = resolver
	return resolver
end

---------------------------------------------------------------------
-- Per-player service used by BlockParryServerInit
---------------------------------------------------------------------

-- We don’t actually need to store the per-player services here, but we keep the
-- API surface expected by BlockParryServerInit: .new(player) and .Remove(player).

function BlockParryService.new(player: Player)
	local svc = {}
	svc.Player = player

	local function getHumanoid(): Humanoid?
		local character = player.Character
		if not character then
			return nil
		end
		return character:FindFirstChildOfClass("Humanoid")
	end

	-- action: "Begin" or "End"
	function svc:HandleBlockRequest(action: string)
		local hum = getHumanoid()
		if not hum then
			return
		end

		if action == "Begin" then
			hum:SetAttribute("IsBlocking", true)
			-- You can tune this or move it into a config module later.
			if hum:GetAttribute("BlockDamageMultiplier") == nil then
				hum:SetAttribute("BlockDamageMultiplier", BlockParryConfig.BlockDamageReduction or 0.5)
			end
		elseif action == "End" then
			hum:SetAttribute("IsBlocking", false)
		end
	end

	-- timestamp is os.clock() from the client; we only use a simple window for now.
	function svc:HandleParryRequest(timestamp: number)
		local hum = getHumanoid()
		if not hum then
			return
		end

		-- Simple parry window: mark parrying for a short time.
		hum:SetAttribute("IsParrying", true)

		task.delay(0.25, function()
			if hum.Parent and hum:GetAttribute("IsParrying") then
				hum:SetAttribute("IsParrying", false)
			end
		end)
	end

	return svc
end

function BlockParryService.Remove(player: Player)
	-- No persistent per-player state stored here yet; keeping this so
	-- BlockParryServerInit: PlayerRemoving -> BlockParryService.Remove(player) is safe.
end

return BlockParryService
