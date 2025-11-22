# ShapecastHitbox Usage for Remnath

We use **ShapecastHitbox** for client-side melee hit detection.

## Attachments

- Each melee weapon / Fists handle must have at least one `Attachment` named or tagged `"DmgPoint"`.
- ShapecastHitbox automatically uses these segments.

## Construction

For Fists, we want ONE persistent hitbox per tool on the **client**:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ShapecastHitbox = require(ReplicatedStorage.Modules.ShapecastHitbox)
local player = Players.LocalPlayer

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = { player.Character }

local hitbox = ShapecastHitbox.new(fistsHandle, raycastParams)
