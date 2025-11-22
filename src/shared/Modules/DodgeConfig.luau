-- Shared tuning for the dodge/roll system so client and server stay in sync.
local DodgeConfig = {}

DodgeConfig.BaseDistance = 7
DodgeConfig.MomentumMultiplier = 0.35
DodgeConfig.MaxRollDistance = 13

-- Time spent granting invulnerability on startup (seconds).
DodgeConfig.IframeDuration = 0.15

-- Total cooldown between dodges (seconds).
DodgeConfig.DodgeCooldown = 0.6

-- Duration of the roll movement itself (seconds).
DodgeConfig.RollDuration = 0.45

-- Recovery applied when you collide with another player mid-roll (seconds).
DodgeConfig.CollisionRecovery = 0.25

-- Attribute names checked to block/strip i-frames when status effects are active.
DodgeConfig.InhibitAttributes = {
	"Hitstunned",
	"Ragdolled",
	"Stunned",
	"ComboLocked",
}

return DodgeConfig
