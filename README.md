# Roll-a-Stream

A Roblox gacha-idle game: spin to collect streamer creators, earn passive
income based on rarity, manage a side-bar inventory. See
[`MEGA_DESIGN.md`](./MEGA_DESIGN.md) for the full design doc and roadmap.

**Built so far:** Phase 1 (core spin/income/inventory loop), Phase 2 (a
production-grade, server-authoritative backend rebuild: profiles, saving,
sessions, economy, validation, and content-ready expansion hooks), and Phase 4
(the Two-Tier Presentation System: instant Standard reveals for Common through
Legendary, cinematic Flagship reveals for Mythic and Secret). Gameplay and odds
are unchanged; presentation never touches income.

## Project layout

```
default.project.json                     Rojo project (build/sync map) + Remotes
src/
  ReplicatedStorage/Modules/
    Configuration/
      GameConfig.lua        All balancing values (autosave, cooldown, $10T cap, multipliers)
      RarityConfig.lua      7 tiers: color, income scaling, sort priority, reveal presets
      PresentationConfig.lua  Two-Tier reveal routing: Flagship vs Standard, chimes, timeouts
      StreamerDatabase.lua  25 streamers + derived rarity/income/weight/presentation_type
      WorldConfig.lua       Valid Collections / Banners / Regions
    Shared/
      NumberFormatter.lua   K/M/B/T formatting (intentionally stops at T)
  Assets/Presentation/                     Folder tree for reveal assets (particles, banners, audio)
  ServerScriptService/                    (mapped into ServerScriptService as "Server")
    Bootstrap.server.lua    Validates config, wires services, starts the game
    Core/         Services (registry), Runtime, StateSync, ExpansionHooks
    Utilities/    Logger, TableUtil, RNG, Validation
    Data/         ProfileTemplate, ProfileService (load/validate/repair), SaveManager
    Economy/      EconomyService (only currency mutator), IncomeService (only income calc)
    Inventory/    InventoryService (stacking + sorting), CollectionService
    Player/       SessionTracker, PlayerManager (lifecycle + loops)
    Networking/   NetworkService (authoritative remotes, validation, deltas)
  StarterPlayer/StarterPlayerScripts/
    ClientBootstrap.client.lua            Entry point; wires remotes -> controllers
    Client/Controllers/  StateController, SpinController, RevealController,
                         StandardRevealHandler, FlagshipRevealHandler
    Client/UI/           HUDController, InventoryController
```

`ReplicatedStorage/Remotes` (`ClientReady`, `SpinRequest`, `SpinResult`,
`InitialState`, `StateUpdate`) is defined directly in `default.project.json`.
Rojo creates those `RemoteEvent` instances on sync.

## Architecture at a glance

- **Server-authoritative.** The client only requests a spin; the server rolls,
  awards, and validates everything. Currency/inventory/income are never trusted
  from the client.
- **One place for everything.** Currency changes only in `EconomyService`,
  income only in `IncomeService`, randomness only in `RNG`, rarity only in
  `RarityConfig`, balancing only in `Configuration/`.
- **Safe saves.** Profiles validate + auto-repair on load, autosave every 60s,
  save on leave/shutdown, never overwrite on a failed load, retry with backoff.
- **Scales to content.** Empty expansion hooks (`ExpansionHooks`) let future
  systems plug into rolls, income, and events without touching core code.
- **Two-Tier presentation.** The server attaches a `PresentationType` to each
  spin result; the client only routes visuals from it. Common through Legendary
  get an instant static reveal (shared rarity color + chime, zero motion). Mythic
  and Secret get a bounded, input-locked cinematic that always cleans up and
  unlocks, and falls back to the instant reveal if its assets are missing.
  Presentation never feeds odds or income.

## Running it in Roblox Studio

1. Install [Rojo](https://rojo.space/docs/v7/getting-started/installation/)
   (CLI + the Roblox Studio plugin).
2. From the repo root: `rojo serve`
3. In Studio, open the Rojo plugin and click **Connect**.
4. Press Play. Spinning, income, collection progress and stacking all work.
   Saving uses real `DataStoreService`: enable **Game Settings > Security >
   Enable Studio Access to API Services** to test persistence in Studio
   (without it, saves safely no-op and each Play session starts fresh).

Or build a standalone place file:

```
rojo build -o RollAStream.rbxlx
```

then open `RollAStream.rbxlx` in Studio.
