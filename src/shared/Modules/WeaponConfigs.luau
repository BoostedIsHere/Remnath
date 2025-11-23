-- src/shared/Modules/WeaponConfigs.luau
-- Central place for per-weapon configs (hitboxes, damage, timings, etc.)

local WeaponConfigs = {}

-- R6 Fists config
WeaponConfigs.Fists = {
    Name = "Fists",

    -- These hitboxes use the attachments you placed on the arms:
    --  Right Arm.RightFist_Start
    --  Right Arm.RightFist_End
    --  Left Arm.LeftFist_Start
    --  Left Arm.LeftFist_End
    Hitboxes = {
        {
            Limb = "Right Arm",
            StartAttachmentName = "RightFist_Start",
            EndAttachmentName   = "RightFist_End",
            Radius = 0.6,   -- was 1.25
            Extend = 0.5,
        },
        {
            Limb = "Left Arm",
            StartAttachmentName = "LeftFist_Start",
            EndAttachmentName   = "LeftFist_End",
            Radius = 0.6,
            Extend = 0.5,
        },
    },

    -- Animation names for the combo chain (matches Tool.Animations children)
    Combo = { "P1", "P2", "P3", "P4" },

    -- Basic combat numbers (tweak these later)
    Damage = { 10, 12, 15, 18 }, -- HP per hit, per swing
    Knockback = { 0, 0, 0, 14 }, -- studs of pushback
    StunTime = 0.3,              -- seconds of stagger
    SwingDuration = 0.35,        -- active hitbox window per swing
    Cooldown = 0.5,              -- time between punches (seconds)
    ActiveFrames = { 0.1, 0.1, 0.12, 0.14 },
    WindupTime = 0.1,
    ActiveTime = 0.12,
    RecoveryTime = 0.25,
    M1Recovery = 0.25,
    Hand = "RightHand",

    -- Server-side validation sizes (mirrors legacy Config)
    Range = 4,

    -- Client-side Shapecast (visual + hit) tuning for fists
    HitboxSize = Vector3.new(0.4, 0.4, 0.4), -- unused for Spherecast, but fine
    HitboxOffset = CFrame.new(),             -- attachments define position
    ServerValidationScale = 0.85,
    CastType = "Spherecast",
    HitboxRadius = 0.6,                      -- keep in sync with Hitboxes[*].Radius

    -- Use Character as the shapecast root so tagged fist attachments become segments
    CastRoot = "Character",
}

return WeaponConfigs
