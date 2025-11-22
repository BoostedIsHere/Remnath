-- Shared tuning for block and parry windows so both client and server stay in sync.
local Config = {}

Config.BlockDamageReduction = 0.2
Config.BlockBreakHits = 3
Config.BlockBreakStun = 0.4

Config.ParryStartup = 0.06
Config.ParryActive = 0.08
Config.ParryPerfect = 0.03
Config.ParryRecovery = 0.25
Config.ParryStun = 0.5
Config.PerfectParryStun = 1.2
Config.PerfectAdvantage = 0.4

return Config
