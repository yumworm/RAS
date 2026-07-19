# Roll-a-Stream

A Roblox gacha-idle game: spin to collect streamer creators, earn passive
income based on rarity, manage a side-bar inventory. See
[`MEGA_DESIGN.md`](./MEGA_DESIGN.md) for the full design doc and roadmap.
Only **Phase 1** (the core spin/income/inventory loop) is implemented.

## Project layout

```
default.project.json                              Rojo project (build/sync map)
src/
  ReplicatedStorage/Modules/
    StreamerData.lua       25-streamer roster + derived rarity/weight/income
    RarityConfig.lua       Tier ranges, colors, income multipliers, odds math
    GameConfig.lua         Shared constants (currency name, timings, cap)
    NumberFormatter.lua    K/M/B/T currency formatting
    WeightedSpin.lua       Server-authoritative weighted roll
  ServerScriptService/
    GachaService.server.lua   Spin handling, income loop, leaderstats, saves
  StarterPlayer/StarterPlayerScripts/
    MainHUD.client.lua     Builds the HUD, drives the spin animation
```

`ReplicatedStorage/Remotes` (`SpinRequest`, `SpinResult`) is defined
directly in `default.project.json` — Rojo creates those `RemoteEvent`
instances on sync, no extra files needed.

## Running it in Roblox Studio

1. Install [Rojo](https://rojo.space/docs/v7/getting-started/installation/)
   (CLI + the Roblox Studio plugin).
2. From the repo root, start the sync server:
   ```
   rojo serve
   ```
3. In Roblox Studio, open the Rojo plugin panel and click **Connect**.
4. Press Play to test. Spinning, income, and saves all work in Studio (Play
   Solo uses real `DataStoreService` if API access is enabled for the
   place, otherwise saves will no-op with a warning).

Alternatively, build a standalone place file without the live plugin:

```
rojo build -o RollAStream.rbxlx
```

Then open `RollAStream.rbxlx` directly in Studio.
