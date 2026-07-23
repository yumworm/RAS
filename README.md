# Roll-a-Stream

A Roblox gacha-idle game: spin to collect streamer creators, earn passive
income based on rarity, manage a side-bar inventory. See
[`MEGA_DESIGN.md`](./MEGA_DESIGN.md) for the full design doc and roadmap.

**Built so far:** Phase 1 (core spin/income/inventory loop), Phase 2 (a
production-grade, server-authoritative backend rebuild: profiles, saving,
sessions, economy, validation, and content-ready expansion hooks), Phase 3 (one
shared Global Donation Stand: donate real Robux via secure, idempotent
`ProcessReceipt` crediting and climb a global all-time Top 100 Donors board
backed by an OrderedDataStore; a support path only, granting zero Streamer Bucks
and never touching the capped Bucks economy), Phase 4 (the Two-Tier Presentation
System: instant Standard reveals for Common through Legendary, cinematic Flagship
reveals for Mythic and Secret), and Phase 5 (the 1.0 launch-polish wrapper:
frictionless first-time experience, a settings menu with a central audio bus,
cross-device UI scaling, and developer-only economy / funnel analytics).
Gameplay and odds are unchanged; presentation never touches income, and Phase 5
adds no new mechanics, currencies, or monetization. Phase 5's donation-aware
seams (funnel logging, a donation-sound hook on the audio bus, donation /
leaderboard scaling, stand lighting) wire directly into the Phase 3 stand.

## Project layout

```
default.project.json                     Rojo project (build/sync map) + Remotes
src/
  ReplicatedStorage/Modules/
    Configuration/
      GameConfig.lua        All balancing values (autosave, cooldown, $10T cap, multipliers)
      GameSettingsConfig.lua  Phase 5 polish tuning: FTUE copy, audio bus defaults, analytics thresholds, UI sizes
      RarityConfig.lua      7 tiers: color, income scaling, sort priority, reveal presets
      PresentationConfig.lua  Two-Tier reveal routing: Flagship vs Standard, chimes, timeouts
      StreamerDatabase.lua  25 streamers + derived rarity/income/weight/presentation_type
      WorldConfig.lua       Valid Collections / Banners / Regions
      DonationConfig.lua    Robux amounts, product IDs, board/cooldown/UI tuning, copy
    Shared/
      NumberFormatter.lua   K/M/B/T for Bucks (stops at T); FormatRobux is uncapped (Qa+)
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
    Donation/     RobuxDonationSystem (prompts + ProcessReceipt + credit),
                  DonationLeaderboard (OrderedDataStore + Top 100 cache),
                  GlobalDonationStandSystem (the one world stand + board)
    Systems/      Analytics/AnalyticsMonitorSystem (dev-only economy + funnel logs)
  StarterPlayer/StarterPlayerScripts/
    ClientBootstrap.client.lua            Entry point; wires remotes -> controllers
    Client/Controllers/  StateController, SpinController, RevealController,
                         StandardRevealHandler, FlagshipRevealHandler,
                         DonationController (panel + Donate button),
                         DonationLeaderboardController (Top 100 panel),
                         AudioController, SettingsController, FTUEController
    Client/UI/           HUDController, InventoryController
```

`ReplicatedStorage/Remotes` (`ClientReady`, `SpinRequest`, `SpinResult`,
`InitialState`, `StateUpdate`, `RequestUpdateSettings`, plus the donation set
`RequestDonationPrompt`, `DonationPromptResult`, `RequestGlobalDonorLeaderboard`,
`GlobalDonorLeaderboardUpdated`, `DonationNotification`, `DonationStandEffect`,
`OpenDonationPanel`) is defined directly in `default.project.json`. Rojo creates
those `RemoteEvent` instances on sync.

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
- **Launch polish (Phase 5).** Players drop straight into the world (no menu
  gate). A first-join welcome toast auto-fades and a gentle pulse sits on the
  Spin button until the first server-confirmed spin. A gear opens a Master /
  Music / SFX settings panel; the server validates and persists those preference
  booleans (and nothing else), and a central client `AudioController` owns the
  looping BGM and a one-shot SFX bus so every Phase 4 reveal sound obeys the
  toggles. Server-side `AnalyticsMonitorSystem` logs (developers only) when Bucks
  cross the ~10T soft cap and exposes a rate-limited donation-funnel API for a
  future Phase 3. Because this environment cannot run Studio, the phone/tablet
  layout emulator matrix (Phase 5 Section 12.3) remains a human verification
  step; the structural scaling (size constraints, min touch targets) is in place.

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
