# Publishing checklist

This document lists every step required to take Roll-a-Stream from the source in
this repository to a live, published Roblox experience. The code is feature
complete; the items below are the human-only steps that cannot be done from the
repository (real Roblox asset ids, Developer Products, Studio settings, and the
Studio test matrix), plus the recommended pre-launch verification.

Work top to bottom. Nothing here changes gameplay balance or scope; it only wires
real Roblox ids into the config modules and confirms the build is healthy.

## 1. Build the toolchain

Tool versions are pinned in `rokit.toml`. With [Rokit](https://github.com/rojo-rbx/rokit)
installed:

```
rokit install
```

This puts matching `rojo`, `stylua`, `selene`, and `luau-lsp` on your PATH. The
same versions run in CI (`.github/workflows/ci.yml`).

Sanity check the project locally:

```
stylua --check src            # formatting gate (must pass)
rojo build default.project.json -o build.rbxl   # compile gate (must pass)
```

## 2. Roblox place and Studio settings

1. Create the place (or use the existing one) on the Creator Dashboard.
2. In Studio: Game Settings > Security, enable **Enable Studio Access to API
   Services** so DataStores work while testing. The live game uses DataStores for
   saves, the donor OrderedDataStore, and donation receipt idempotency.
3. In Studio: Game Settings > Permissions, set the experience to **Public** only
   when you are ready to go live.
4. Confirm **Allow Third Party Sales** is not required (this game sells only its
   own Developer Products, not third-party assets).

## 3. Developer Products (donations)

The Global Donation Stand sells eight fixed Robux amounts. Until each product id
is a real, non-zero value the server refuses to prompt that amount and logs a
startup warning; this is by design so you can never accidentally ship a broken
prompt.

1. On the Creator Dashboard, create one Developer Product per amount:
   `5, 10, 25, 50, 100, 250, 500, 1000` Robux.
2. Paste each real product id into `DonationConfig.ProductIds`
   (`src/ReplicatedStorage/Modules/Configuration/DonationConfig.lua`). Replace
   every `0`.
3. Do not change the amounts or add new ones without a scope decision. The amount
   set is the single source of truth and the client only ever sends an amount, the
   server maps amount to product id.

## 4. Presentation asset ids (optional but recommended)

These use the `rbxassetid://0` dev placeholder and degrade gracefully (the client
skips a missing image/sound), so they are not launch blockers. Startup validation
logs a warning for each placeholder so none is forgotten.

- Flagship streamer presentation (`StreamerDatabase.lua`): `banner_asset`,
  `reveal_animation_id`, `reveal_sound`, `particle_preset`, `card_background`.
- Per-rarity reveal sounds (`PresentationConfig.RarityChimes`).
- Optional donation success sound (`DonationConfig.Effects.SuccessSoundId`, `""`
  means no sound).
- Optional background music (`GameSettingsConfig.Audio.BgmSoundId`, `""` means no
  BGM, which is a valid choice, not an error).

Upload the assets, then drop the ids into these fields. Empty and placeholder ids
are safe to ship; they simply mean "no visual/audio for that slot yet".

## 5. Live content and feature flags

Review `LiveContentConfig.lua` before launch:

- `FeatureFlags` are booleans that cleanly hide the matching UI. Ship with the set
  you want live (all default to on).
- `Featured` is a cosmetic text badge only and never touches the RNG, income, or
  weights. Leave `Enabled = false` unless you are running a highlight; set
  `StreamerName` to an exact roster name and an optional `EndTimestamp`.
- `ReturnSummary` is facts-only and performs zero economy writes (no offline
  income). Confirm `MinAwaySec` is the threshold you want.

## 6. Logging

`GameConfig.LoggingEnabled` now defaults to on in Studio and off in live/published
servers (`RunService:IsStudio()`), so a shipped game does not spam the console. To
force logs on in a live server for a one-off investigation, set it to an explicit
`true` and republish.

## 7. Studio test matrix (run before going public)

Run each in Studio (Play Solo and, where noted, Local Server with 2 players).

- New player: first join runs the FTUE welcome toast; the return summary is
  suppressed on the very first session.
- Returning player: log out, wait past `ReturnSummary.MinAwaySec`, rejoin, confirm
  the welcome-back panel shows facts only and no currency is granted for time away.
- Spin / reveal: standard and Flagship reveals play; placeholder assets skip
  cleanly without errors.
- Donations (2-player Local Server): a successful donation updates the donor's
  RobuxDonatedLifetime, the Top 100 board, and pushes a live feed row to both
  clients. Confirm the feed row reads "<donor> donated <amount> Robux" with no
  receiver token.
- Idempotency: donations credit exactly once even if a receipt is reprocessed.
- Profile cards: clicking a leaderboard row opens the server-authored card;
  offline targets fall back to the minimal public snapshot.
- Settings: toggles for music, SFX, master, donation feed, and return summary
  persist across rejoin.
- Mobile: use the Studio Device Emulator (phone and tablet) and confirm UI scales,
  primary buttons stay at least `LiveContentConfig.UI.MinTouchPx` tall, and nothing
  overflows.

## 8. Publish

1. `rojo build default.project.json -o build.rbxl`, open in Studio, and publish to
   the place; or use `rojo upload` with your target place id.
2. Verify the CI run on the merge is green (format + build gates).
3. Flip the experience to Public.

## 9. Known follow-ups (not launch blockers)

- **Strict type-check burn-down.** `luau-lsp analyze` currently reports strict-mode
  findings (mostly optional-nil narrowing and `Instance?` UI locals). CI runs the
  type check as **advisory** (non-blocking). These are annotation-level issues and
  do not affect runtime behavior; the place compiles and runs. Burn the count down
  over time, then flip the CI type-check step to a blocking gate.
- **selene lint** runs advisory in CI for the same reason.
