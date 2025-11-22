-- Bootstraps client-side systems (dodge, etc).

-- Handle both flat placement under PlayerScripts and nested "Client" folder.
local root = script.Parent
if not root:FindFirstChild("Input") and root:FindFirstChild("Client") then
	root = root:WaitForChild("Client")
end

local movementInput = require(root:WaitForChild("Input"):WaitForChild("MovementInput")).new()
require(root:WaitForChild("Controllers"):WaitForChild("DodgeController")).new(movementInput)
require(root:WaitForChild("Controllers"):WaitForChild("BlockParryController")).new()

print("[Client] systems initialized")
