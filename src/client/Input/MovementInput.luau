-- Captures double-tap and Shift + direction inputs to request dodges.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local directionMap = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
}

local MovementInput = {}
MovementInput.__index = MovementInput

function MovementInput.new()
	local self = setmetatable({}, MovementInput)
	self.Player = Players.LocalPlayer
	self.Humanoid = nil

	self._event = Instance.new("BindableEvent")
	self.pressedDirections = {}

	self.inputBeganConn = UserInputService.InputBegan:Connect(function(input, gp)
		self:onInputBegan(input, gp)
	end)

	self.inputEndedConn = UserInputService.InputEnded:Connect(function(input, gp)
		self:onInputEnded(input, gp)
	end)

	return self
end

function MovementInput:Destroy()
	if self.inputBeganConn then
		self.inputBeganConn:Disconnect()
		self.inputBeganConn = nil
	end
	if self.inputEndedConn then
		self.inputEndedConn:Disconnect()
		self.inputEndedConn = nil
	end
	if self._event then
		self._event:Destroy()
		self._event = nil
	end
end

function MovementInput:BindCharacter(character)
	self.Humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
end

function MovementInput:GetSignal()
	return self._event.Event
end

function MovementInput:getMoveDirection()
	if self.Humanoid then
		return self.Humanoid.MoveDirection
	end

	return Vector3.new()
end

function MovementInput:onInputBegan(input, gp)
	if gp then
		return
	end

	if directionMap[input.KeyCode] then
		self.pressedDirections[input.KeyCode] = true
	end

	if input.KeyCode ~= Enum.KeyCode.Q then
		return
	end

	local moveDir = self:getMoveDirection()

	-- If MoveDirection is tiny (e.g., just started pressing a key, or stationary),
	-- fall back to current directional key intent.
	if moveDir.Magnitude < 0.05 then
		local summed = Vector3.new()
		for key, dir in pairs(directionMap) do
			if self.pressedDirections[key] then
				summed += dir
			end
		end
		moveDir = summed
	end

	self._event:Fire(moveDir)
end

function MovementInput:onInputEnded(input, gp)
	if gp then
		return
	end

	if directionMap[input.KeyCode] then
		self.pressedDirections[input.KeyCode] = nil
	end
end

return MovementInput
