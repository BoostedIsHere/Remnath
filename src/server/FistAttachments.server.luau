local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Folder in ReplicatedStorage:
-- ReplicatedStorage.FistAttachmentTemplates
--   Right Arm
--     RightFist_Start (Attachment)
--     RightFist_End   (Attachment)
--   Left Arm
--     LeftFist_Start  (Attachment)
--     LeftFist_End    (Attachment)

local TEMPLATES_FOLDER_NAME = "FistAttachmentTemplates"

local templatesFolder = ReplicatedStorage:WaitForChild(TEMPLATES_FOLDER_NAME)

local function applyFistAttachmentsToCharacter(character: Model)
    -- Go through each limb folder in the templates
    for _, limbTemplate in ipairs(templatesFolder:GetChildren()) do
        local limbName = limbTemplate.Name -- "Right Arm", "Left Arm"
        local limb = character:FindFirstChild(limbName)

        if limb then
            for _, attachmentTemplate in ipairs(limbTemplate:GetChildren()) do
                if attachmentTemplate:IsA("Attachment") then
                    -- Don’t duplicate if it’s already there
                    if not limb:FindFirstChild(attachmentTemplate.Name) then
                        local clone = attachmentTemplate:Clone()
                        clone.Parent = limb
                        -- Tag for ShapecastHitbox so fists casts use these points directly
                        CollectionService:AddTag(clone, "DmgPoint")
                    end
                end
            end
        end
    end
end

local function onCharacterAdded(character: Model)
    -- Wait for limbs to exist
    character:WaitForChild("Right Arm", 5)
    character:WaitForChild("Left Arm", 5)

    applyFistAttachmentsToCharacter(character)
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(onCharacterAdded)
end)

-- Optional: if you're spawning NPCs with the same rig, you can call:
-- applyFistAttachmentsToCharacter(npcModel)
-- from wherever you spawn them.
