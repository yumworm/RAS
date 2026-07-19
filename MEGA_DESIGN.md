# Roll-a-Stream — Mega Design Document

Roll-a-Stream is a Roblox gacha-idle game: players spin to collect streamer
creators, each of which passively earns currency ("Streamer Bucks") based on
how rare they are. Popular streamers are the hardest to roll and pay out the
most.

This document is the living master design reference for the whole game. It
tracks the full roadmap, but **only Phase 1 is built right now.** Later
phases are recorded here as placeholders so future work has a fixed target
to build against — they are not implemented and should not be inferred from
the codebase.

## Roadmap

| Phase | Status | Scope |
|---|---|---|
| **Phase 1 — Core Loop** | ✅ Built | Spin button, weighted gacha roll, 25-streamer roster, passive income, side-bar inventory |
| Phase 2 — Garage | 🔲 Not started | Placeholder — spec TBD |
| Phase 2 — Lucky Spins | 🔲 Not started | Placeholder — spec TBD |
| Phase 2 — Robux Gamepasses | 🔲 Not started | Placeholder — spec TBD |
| Phase 2 — Cinematic reveal cutscenes | 🔲 Not started | Placeholder — spec TBD |
| Phase 2 — Codes system | 🔲 Not started | Placeholder — spec TBD |

Do not build anything below Phase 1 until a phase-specific prompt arrives.

---

## Phase 1 — Core Loop

### Roster philosophy

25 streamers, hand-picked, no filler. Every entry should be a name a player
recognizes on sight. `popularity_score` (1–100) is a **gameplay-balance
value**, not a certified live analytics feed — it's tuned by hand to shape
the odds/income curve, loosely inspired by each creator's real-world
prominence circa 2025–2026.

### Rarity tiers

Derived automatically from `popularity_score` (`RarityConfig.GetTierForPopularity`):

| Tier | Popularity range | Color | Income multiplier |
|---|---|---|---|
| Common | 1–30 | Gray | 1.0x |
| Uncommon | 31–50 | Green | 1.15x |
| Rare | 51–65 | Blue | 1.35x |
| Epic | 66–80 | Purple | 1.6x |
| Legendary | 81–90 | Gold | 2.0x |
| Mythic | 91–97 | Red | 2.6x |
| Secret | 98–100 | Rainbow | 3.5x |

### Roster (25)

| # | Name | Popularity | Tier | Base income | Weight |
|---|---|---|---|---|---|
| 1 | Kai Cenat | 100 | Secret | 200 | 1 |
| 2 | Speed | 99 | Secret | 198 | 2 |
| 3 | xQc | 98 | Secret | 196 | 3 |
| 4 | MrBeast | 97 | Mythic | 194 | 4 |
| 5 | Adin Ross | 95 | Mythic | 190 | 6 |
| 6 | Jynxzi | 93 | Mythic | 186 | 8 |
| 7 | Duke Dennis | 91 | Mythic | 182 | 10 |
| 8 | CaseOh | 88 | Legendary | 176 | 13 |
| 9 | Fanum | 85 | Legendary | 170 | 16 |
| 10 | Ninja | 84 | Legendary | 168 | 17 |
| 11 | Stable Ronaldo | 82 | Legendary | 164 | 19 |
| 12 | Lacy | 75 | Epic | 150 | 26 |
| 13 | JasonTheWeen | 72 | Epic | 144 | 29 |
| 14 | Rakai | 70 | Epic | 140 | 31 |
| 15 | Agent 00 | 68 | Epic | 136 | 33 |
| 16 | Sketch | 66 | Epic | 132 | 35 |
| 17 | Plaqueboymax | 60 | Rare | 120 | 41 |
| 18 | N3on | 58 | Rare | 116 | 43 |
| 19 | Ludwig | 55 | Rare | 110 | 46 |
| 20 | Valkyrae | 53 | Rare | 106 | 48 |
| 21 | Pokimane | 52 | Rare | 104 | 49 |
| 22 | Cinna | 40 | Uncommon | 80 | 61 |
| 23 | Ranboo | 33 | Uncommon | 66 | 68 |
| 24 | Punga | 22 | Common | 44 | 79 |
| 25 | Slime | 18 | Common | 36 | 83 |

`base_income = popularity_score * 2`. Effective income per owned copy is
`base_income * tier.IncomeMultiplier`, and stacks linearly with duplicates.

### Odds

Roll weight is inverse to popularity: `weight = 101 - popularity_score`
(popularity 100 → weight 1, popularity 20 → weight 81). Total weight across
the roster is 771, giving these tier-level roll probabilities:

| Tier | Probability |
|---|---|
| Secret | 0.78% |
| Mythic | 3.63% |
| Legendary | 8.43% |
| Epic | 19.97% |
| Rare | 29.44% |
| Uncommon | 16.73% |
| Common | 21.01% |

### Spin flow

1. Player clicks **Spin** → client fires `SpinRequest` and immediately starts
   a cosmetic reel (random cards cycling every ~0.04s, ramping to ~0.26s
   over ~2 seconds).
2. Server rolls a **weighted random winner** (`WeightedSpin.Roll`), adds it
   to the player's owned collection (stacking duplicates), recomputes their
   income/sec, and fires `SpinResult` back with the winner + a full
   inventory snapshot.
3. Client waits for both the animation minimum and the server response,
   then locks the reel onto the true winner with a scale-pop, a
   rarity-colored glow, and a particle burst (extra rainbow treatment for
   Secret).
4. The side-bar inventory and income/sec label update from the
   server-provided snapshot — the client never invents its own economy
   state.

### Income system

- Every server heartbeat accumulates elapsed time; once it crosses
  `IncomeTickInterval` (1s), each player's currency increases by their
  total income/sec (sum of all owned streamers' effective income),
  clamped to the Phase 1 economy cap.
- Currency lives on `leaderstats` (`NumberValue` named `"Streamer Bucks"`)
  so it's visible in the native Roblox leaderboard.
- The client shows a floating `+N` popup near the currency label whenever
  it increases.

### Economy rules (Phase 1 only)

- Range: **$0 – $1,000,000** (`GameConfig.EconomyCap`). No inflation
  beyond that yet.
- Number formatting supports K/M now, with B/T already wired in for later
  phases (`NumberFormatter`).

### Explicitly out of scope for Phase 1

Garage, Lucky Spins, Robux Gamepasses, cinematic reveal cutscenes, and the
Codes system. Do not build these until a dedicated Phase 2 prompt.

### Future-field placeholders

Each streamer record already carries empty/false placeholders for fields
Phase 2+ will use, so later work doesn't require a data migration:
`collection`, `banner`, `region`, `is_featured`, `reveal_animation_id`,
`reveal_sound`, `card_background`, `particle_preset`. None of these are
read or rendered anywhere yet.

---

## Tech architecture

- **Engine**: Roblox, synced via [Rojo](https://rojo.space/) (`default.project.json`).
- **Data**: `ReplicatedStorage/Modules` — pure ModuleScripts, safe to
  `require` from both server and client (`StreamerData`, `RarityConfig`,
  `GameConfig`, `NumberFormatter`, `WeightedSpin`).
- **Networking**: `ReplicatedStorage/Remotes` — `SpinRequest` (client→server
  `RemoteEvent`) and `SpinResult` (server→client `RemoteEvent`).
- **Server**: `ServerScriptService/GachaService.server.lua` — owns the roll,
  income accrual loop, leaderstats, and `DataStoreService` persistence
  (save on leave / `BindToClose`).
- **Client**: `StarterPlayer/StarterPlayerScripts/MainHUD.client.lua` —
  builds the entire HUD from code (no pre-built GUI assets needed), drives
  the spin animation with `TweenService`, and renders the inventory
  sidebar.

See `README.md` for how to sync this into Roblox Studio.
