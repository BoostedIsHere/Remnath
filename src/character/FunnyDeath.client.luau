-- Plays a temporary death animation for fun + debug helpers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")

-- Keep the rig intact on death so the animation can play without limbs popping off.
humanoid.BreakJointsOnDeath = false

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

print("[FunnyDeath] Init for", character.Name)

local animationsFolder = ReplicatedStorage:WaitForChild("Animations")
local function loadFunnyTrack()
	local animFolder = animationsFolder or ReplicatedStorage:FindFirstChild("Animations")
	if not animFolder then
		return nil
	end

	local funnyAnim = animFolder:FindFirstChild("FunnyDeath")
	if not funnyAnim then
		warn("[FunnyDeath] FunnyDeath animation not found in ReplicatedStorage/Animations")
		return nil
	end
	if not funnyAnim.AnimationId or funnyAnim.AnimationId == "" then
		warn("[FunnyDeath] FunnyDeath AnimationId is empty")
		return nil
	end

	local track = animator:LoadAnimation(funnyAnim)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:AdjustSpeed(0.1) -- very slow playback
	print("[FunnyDeath] Loaded FunnyDeath animation. Length =", track.Length)
	return track
end

local funnyTrack = loadFunnyTrack()

humanoid.Died:Connect(function()
	print("[FunnyDeath] Humanoid.Died fired, playing FunnyDeath")

	-- Nuke default Animate's death track so ours shows.
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate.Disabled = true
	end

	-- Keep camera anchored to the body even if the head detaches.
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraSubject = hrp or humanoid
	end

	-- Stop any active tracks so the death anim is visible.
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0.05)
	 end

	-- If the original track failed, try reloading now (in case the asset replicated late).
	if not funnyTrack then
		funnyTrack = loadFunnyTrack()
	end

	if funnyTrack then
		funnyTrack:AdjustSpeed(0.1)
		funnyTrack:Play(0.05)
	else
		warn("[FunnyDeath] Cannot play FunnyDeath; track missing")
	end
end)
