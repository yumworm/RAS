local GameConfig = {}

GameConfig.CurrencyName = "Streamer Bucks"
GameConfig.StartingCurrency = 0
GameConfig.SpinAnimationDuration = 2 -- seconds, cosmetic reel minimum before landing
GameConfig.SpinCooldown = 0.5 -- seconds, blocks remote spam
GameConfig.IncomeTickInterval = 1 -- seconds
GameConfig.EconomyCap = 1000000 -- Phase 1 soft cap: $0 to $1M only

return GameConfig
