-- AnimationDebug (StarterPlayerScripts)
-- Logs animation start/stop on the local humanoid and lets you dump currently
-- playing tracks with F8. Helps track down default tool/idles overriding stance.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ENABLED = true -- toggle off to silence the logger
local DUMP_KEY = Enum.KeyCode.F8
local TAG = "[AnimDebug]"

-- Known default tool animations that often override custom idles
local DEFAULT_TOOL_ANIMS = {
	["rbxassetid://182393478"] = "ToolNone",
	["rbxassetid://182393474"] = "ToolSlash",
	["rbxassetid://182393482"] = "ToolLunge",
}

local player = Players.LocalPlayer

local characterConns = {}
local trackStopConns = {}

local function disconnectAll(tbl)
	for _, conn in ipairs(tbl) do
		conn:Disconnect()
	end
	table.clear(tbl)
end

local function describeTrack(track)
	local anim = track.Animation
	local id = anim and anim.AnimationId or "nil"
	local name = anim and anim.Name or track.Name or "?"
	local priority = track.Priority and track.Priority.Name or "?"
	local defaultTag = DEFAULT_TOOL_ANIMS[id] and ("<DEFAULT:" .. DEFAULT_TOOL_ANIMS[id] .. ">") or ""
	return string.format("%s name=%s id=%s priority=%s weight=%.2f", defaultTag, name, id, priority, track.WeightCurrent or 0)
end

local function dumpPlaying(humanoid)
	local tracks = humanoid:GetPlayingAnimationTracks()
	warn(TAG, "Currently playing", #tracks, "tracks")
	for _, track in ipairs(tracks) do
		warn(TAG, " ", describeTrack(track))
	end
end

local function bindHumanoid(humanoid)
	if not humanoid then
		return
	end

	-- ensure animator exists so AnimationPlayed fires for tracks we start
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	table.insert(characterConns, humanoid.AnimationPlayed:Connect(function(track)
		warn(TAG, "Play", describeTrack(track))
		local stopConn
		stopConn = track.Stopped:Connect(function()
			warn(TAG, "Stop", describeTrack(track))
			if stopConn then
				stopConn:Disconnect()
			end
		end)
		table.insert(trackStopConns, stopConn)
	end))

	table.insert(characterConns, UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == DUMP_KEY then
			dumpPlaying(humanoid)
		end
	end))

	-- Small delay to give the character time to finish spawning, then dump initial tracks
	task.delay(0.5, function()
		if humanoid.Parent then
			dumpPlaying(humanoid)
		end
	end)
end

local function onCharacterAdded(character)
	disconnectAll(characterConns)
	disconnectAll(trackStopConns)

	local humanoid = character:WaitForChild("Humanoid")
	bindHumanoid(humanoid)
end

if ENABLED then
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
else
	script:Destroy()
end
