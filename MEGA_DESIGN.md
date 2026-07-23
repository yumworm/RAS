# Roll-a-Stream: Mega Design Document

Roll-a-Stream is a Roblox gacha-idle game: players spin to collect streamer
creators, each of which passively earns currency ("Streamer Bucks") based on
how rare they are. Popular streamers are the hardest to roll and pay out the
most.

This document is the living master design reference for the whole game. It
tracks the full roadmap; the **Status** column says what's actually built.

## Roadmap

| Phase | Status | Scope |
|---|---|---|
| **Phase 1: Core Loop** | Built | Spin button, weighted gacha roll, 25-streamer roster, passive income, side-bar inventory |
| **Phase 2: Backend Foundation** | Built | Production-grade rebuild: profiles, saving, sessions, inventory, collection, economy, RNG, config, server authority, networking, validation, lifecycle, expansion hooks |
| Phase 3: Progression systems | Not started | Placeholder, spec TBD |
| **Phase 4: Two-Tier Presentation** | Built | Presentation finalization: server-attached PresentationType, instant Standard reveal (Common-Legendary), cinematic Flagship reveal (Mythic/Secret), startup presentation validation, roster locked to 20-30 |

Phase 2 was a **backend-only** rebuild. A player barely notices a gameplay
difference versus Phase 1, but the systems underneath are now scalable,
server-authoritative, and ready for content without rewrites.

Phase 4 is presentation-only: it splits the reveal path into two tiers by rarity
without touching odds or income. The scrapped legacy Phase 4 draft (roster
expansion to 100-150, Regions, Banner gacha, Collections rewards, pity) is
explicitly out of scope; the roster stays a tight 20-30 and rolls stay pure
inverse-popularity RNG.

Do not build the remaining Phase 3+ gameplay (Garage, Lucky Spins, Gamepasses,
Codes, Trading, Quests, Events) until a phase-specific prompt arrives; only the
backend *seams* those systems will use exist today (see Expansion Hooks below).

---

## Project-wide economy rule

The economy **intentionally ends around $10T**. This is a hard design
constraint, not a placeholder.

Progression bands (documented in `GameConfig.ProgressionBands`):

| Band | Range | Feel |
|---|---|---|
| Early | $0 - $1M | Discovering streamers |
| Mid | $1M - $1B | Building the roster |
| Late | $1B - $100B | Chasing Mythics & Secrets |
| End | $100B - ~$10T | Perfect collection, max upgrades |

Number formatting stops at **K, M, B, T**, nothing larger. There is no Qa,
Qi, Sx, etc. If a value ever exceeds T, that is a **balancing bug to fix in
the economy**, not a reason to add a suffix. `EconomyCap` (10e12) hard-clamps
currency, and startup validation asserts the formatter defines exactly the
K/M/B/T set. Future progression comes from *content* (collections, upgrades,
cosmetics, regions, spin machines, challenges, seasonal content), not bigger
numbers.

---

## Roster

25 streamers, hand-picked, no filler. Every entry is a name a player
recognizes on sight. `popularity_score` (1-100) is a **gameplay-balance
value**, tuned by hand and loosely inspired by real-world prominence circa
2025-2026, not a live analytics feed. The backend is built to scale to
~150 streamers without changes.

### Rarity tiers

Derived from `popularity_score` (`RarityConfig.GetTierForPopularity`). Rarity
is a full identity, not just a number; each tier also carries card style,
reveal effects, audio/animation/particle presets, and cinematic/announcement
flags (data-only for now, consumed by a future presentation phase).

| Tier | Popularity | Color | Income scaling |
|---|---|---|---|
| Common | 1-30 | Gray | ×1 |
| Uncommon | 31-50 | Green | ×4 |
| Rare | 51-65 | Blue | ×15 |
| Epic | 66-80 | Purple | ×60 |
| Legendary | 81-90 | Gold | ×250 |
| Mythic | 91-97 | Red | ×1,200 |
| Secret | 98-100 | Rainbow | ×6,000 |

### Roster & income

`base_income = popularity_score`. Effective income per owned copy =
`base_income × rarity.IncomeScaling`, stacking linearly with duplicates and
computed only in `IncomeService`. Scaling is tuned so a maxed roster plus
future upgrade/prestige multipliers approaches the $10T endgame without
exceeding it.

| # | Name | Pop | Tier | Income/sec (per copy) | Weight |
|---|---|---|---|---|---|
| 1 | Kai Cenat | 100 | Secret | 600,000 | 1 |
| 2 | Speed | 99 | Secret | 594,000 | 2 |
| 3 | xQc | 98 | Secret | 588,000 | 3 |
| 4 | MrBeast | 97 | Mythic | 116,400 | 4 |
| 5 | Adin Ross | 95 | Mythic | 114,000 | 6 |
| 6 | Jynxzi | 93 | Mythic | 111,600 | 8 |
| 7 | Duke Dennis | 91 | Mythic | 109,200 | 10 |
| 8 | CaseOh | 88 | Legendary | 22,000 | 13 |
| 9 | Fanum | 85 | Legendary | 21,250 | 16 |
| 10 | Ninja | 84 | Legendary | 21,000 | 17 |
| 11 | Stable Ronaldo | 82 | Legendary | 20,500 | 19 |
| 12 | Lacy | 75 | Epic | 4,500 | 26 |
| 13 | JasonTheWeen | 72 | Epic | 4,320 | 29 |
| 14 | Rakai | 70 | Epic | 4,200 | 31 |
| 15 | Agent 00 | 68 | Epic | 4,080 | 33 |
| 16 | Sketch | 66 | Epic | 3,960 | 35 |
| 17 | Plaqueboymax | 60 | Rare | 900 | 41 |
| 18 | N3on | 58 | Rare | 870 | 43 |
| 19 | Ludwig | 55 | Rare | 825 | 46 |
| 20 | Valkyrae | 53 | Rare | 795 | 48 |
| 21 | Pokimane | 52 | Rare | 780 | 49 |
| 22 | Cinna | 40 | Uncommon | 160 | 61 |
| 23 | Ranboo | 33 | Uncommon | 132 | 68 |
| 24 | Punga | 22 | Common | 22 | 79 |
| 25 | Slime | 18 | Common | 18 | 83 |

### Odds

Roll weight is inverse to popularity: `weight = 101 - popularity_score`.
Total weight is 771, giving these tier-level roll probabilities (rare = popular
= hard to pull):

| Tier | Probability |
|---|---|
| Secret | 0.78% |
| Mythic | 3.63% |
| Legendary | 8.43% |
| Epic | 19.97% |
| Rare | 29.44% |
| Uncommon | 16.73% |
| Common | 21.01% |

### Content assignment & presentation fields

Every streamer carries the fields future content will use, validated on
startup:

- **Collection** (exactly one, all launch streamers are `Originals`)
- **Banners** (at least one, all in `Standard`)
- **Region** (`NA` / `EU` / `SA` / `Global`)
- **Featured** flag (all `false` today)
- **Presentation placeholders** (asset ids, placeholder `rbxassetid://0` in dev):
  `reveal_animation_id`, `reveal_sound`, `banner_asset`, `card_background`,
  `particle_preset`, `voice_line`, `intro_camera_preset`
- **`presentation_type`** (derived, Phase 4): `Flagship` for Mythic/Secret,
  `Standard` for everything else. Never hand-authored; see below.

---

## Two-Tier Presentation System (Phase 4)

Presentation is split into exactly two reveal paths, chosen strictly by rarity.
The split changes only how a pull is shown, never what is rolled or what it
earns. `PresentationConfig` owns the routing (rarity colors stay in
`RarityConfig` so they never drift).

- **Flagship (Mythic, Secret only).** A bounded, input-locked cinematic:
  per-streamer banner, animated sequence, signature sound, and a particle burst.
  It has a hard `MaxSequenceSeconds` timeout, always cleans up its temporary
  instances, always unlocks input (pcall-guarded), and falls back to the Standard
  reveal if its required asset fields are absent. It can never soft-lock the UI.
- **Standard (Common through Legendary).** An instant static pop-in: shared
  rarity color plus a shared rarity chime, with zero winner-card motion (no
  tween, bounce, flip, fade, or `task.wait` for drama) and no per-streamer
  assets. Speed and clarity are the point.

Flow: the server rolls (pure inverse-popularity RNG, unchanged), grants, and
attaches an authoritative `PresentationType` (re-derived from rarity as a safety
net) plus, for Flagship, a read-only `Assets` subset to `SpinResult`. The client
`RevealController` routes on that string alone: Standard results can never reach
the Flagship handler, and the client can never force a Flagship reveal for a
Standard pull. Startup validation enforces roster size (20-30), presentation /
rarity consistency, and Flagship required fields; fatal issues disable the gacha
rather than roll on unsafe content.

---

## Backend architecture (Phase 2)

Everything is server-authoritative. The client may only *request* a spin; the
server decides the winner, the reward, and every stat. Currency, inventory,
roll results, income and statistics are never trusted from the client.

### Player profile

One centralized profile per player (`ProfileTemplate`) is the single source of
saved data; no script keeps its own. It holds economy state, lifetime stats,
best pull, stacked inventory, collection discovery dates, unlocked-feature
gates, settings, and an open `futureFlags` bag. Adding a field to the template
auto-appears (with its default) on every existing save on next load, with no
migration and no wipe.

**Validation & repair** (`ProfileService`): a save is never trusted. On load
every value is checked; missing, wrong type, negative, out of range, or
referencing an unknown streamer is repaired automatically. If the whole load
errors, the player gets safe defaults *and* the session is flagged so
`SaveManager` won't overwrite the (recoverable) real data.

### Saving (`SaveManager`)

Background only, never blocks gameplay. Autosaves every 60s, saves on leave and
on server shutdown. A per-player guard prevents two concurrent writes; a
request mid-save queues exactly one more pass so the latest data always lands.
Failed writes retry with exponential backoff (2/4/8/16s, reduced in Studio).

### Sessions (`SessionTracker`)

Per-join metrics (session earnings, spins, playtime, streamers pulled, session
income/currency highs) live in runtime and reset every join. Lifetime values in
the profile only ever increase.

### Inventory (`InventoryService`)

Stacked: duplicates increment `amount`, never a second entry. The client-facing
view is sorted **server-side** (rarity priority -> popularity -> alphabetical)
so the UI never sorts. Each entry remembers first/most-recent pull and carries
future placeholders (`upgradeLevel`, `xp`, `favorite`, `locked`).

### Collection (`CollectionService`)

Tracks total vs collected vs missing, completion %, first-discovery dates,
duplicate count, and highest rarity owned. Recomputed only when the inventory
changes, never on a loop.

### Economy (`EconomyService`) & income (`IncomeService`)

`EconomyService` is the only thing that changes currency (`AddCurrency` /
`SpendCurrency`), clamped to the $10T cap, keeping all lifetime/highest stats in
sync. `IncomeService` is the only place income/sec is calculated; it recomputes
just when the inventory changes, caches the result, and updates the high-water
mark. All future multipliers (upgrades, boosts, events, gamepasses) fold in via
one hook.

### RNG (`RNG`)

The single random system. One roll function, one weighted selection. Weight is
inverse to popularity, with neutral hooks for future luck / event / pity
modifiers so Lucky Spins, Luck Potions and Weekend Events plug in without
touching core odds. Server-only: clients can't see or influence it.

### Networking (`NetworkService`)

Client sends `SpinRequest` ("I want to spin"); server validates (player exists,
profile loaded & initialized, not mid-roll, off cooldown), decides the winner,
awards it, and replies with `SpinResult` (for the reveal) plus a `StateUpdate`
delta. Spin spam is rejected by the cooldown + in-flight lock. Outbound, the
server sends one full `InitialState` snapshot (handshaked via `ClientReady`),
then only *deltas*: currency ticks up every second as a tiny `{currency}`
update; the (small) inventory is sent only when it changes.

### Lifecycle (`PlayerManager`)

Strict join order: create runtime -> load+validate profile -> compute income ->
start session -> mark initialized (gameplay enabled only now) -> send initial
state. Leaving saves (blocking, with retry) then tears everything down. Shutdown
saves every player and waits for completion, prioritizing data safety. Exactly
two background loops exist: one Heartbeat income accumulator and one autosave
loop.

### Validation on startup (`Validation`)

Before players can hit it, the content is checked: duplicate names, invalid
popularity, missing/negative income, unknown rarity, rarity/popularity drift,
missing or invalid Collection / Banner / Region, non-string presentation
references, featured-without-animation, and that the formatter defines exactly
K/M/B/T. Problems are logged loudly; the game still boots and fails safe.

### Memory & errors

Per-player connections are tracked and disconnected on leave; runtime, profile,
save-state and sync buffers are all dropped so no table grows unbounded across a
long server. Every remote handler and the join/save flows are wrapped so a
malformed request or bad save can never crash the server.

### Expansion hooks (`ExpansionHooks`)

Empty, content-first seams future systems register into without editing core:
`RollModifiers`, `IncomeMultipliers`, `OnStreamerObtained`, `OnSpinCompleted`,
`OnCurrencyChanged`, `FeatureUnlockRules`. They're wired into the RNG, income,
inventory, economy and spin flows today but do nothing until something
registers (content systems are the priority; monetization/analytics are
secondary).

---

## File structure

```
default.project.json                          Rojo map (folders, remotes)
src/
  ReplicatedStorage/Modules/
    Configuration/     GameConfig, RarityConfig, StreamerDatabase, WorldConfig
    Shared/            NumberFormatter (K/M/B/T only)
  ServerScriptService/                         (mapped as ServerScriptService.Server)
    Bootstrap.server.lua                       validates config, wires + starts services
    Core/              Services, Runtime, StateSync, ExpansionHooks
    Utilities/         Logger, TableUtil, RNG, Validation
    Data/              ProfileTemplate, ProfileService, SaveManager
    Economy/           EconomyService, IncomeService
    Inventory/         InventoryService, CollectionService
    Player/            SessionTracker, PlayerManager
    Networking/        NetworkService
  StarterPlayer/StarterPlayerScripts/
    ClientBootstrap.client.lua
    Client/Controllers/  StateController, SpinController
    Client/UI/           HUDController, InventoryController
```

Remotes (`ClientReady`, `SpinRequest`, `SpinResult`, `InitialState`,
`StateUpdate`) are defined in `default.project.json`. Balancing is centralized:
tuning the game means editing `Configuration/`, never hunting through services.

See `README.md` for how to sync this into Roblox Studio.
