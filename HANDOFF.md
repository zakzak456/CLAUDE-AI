# Mom, Look! I Can Mine! — overnight build notes

Place: **"Mom look i can mine"**, placeId 129630483148249 (built 2026-11-09 over MCP only; nothing published, no money spent).

**You must press Ctrl+S in Studio** — nothing is saved to the place file until you do.

## Where things are

| What | Where |
|---|---|
| Server (owns money, ore, levels, managers, unlocks, tutorial progress, saves) | `ServerScriptService.MineServer` (+ `Profiles`, `Sim`) |
| Shared tuning and formulas | `ReplicatedStorage.Mine.Config`, `.Formulas`, `.Remotes` (Request, Sync) |
| Client (2D view, HUD, panel, tutorial, cinematic, sounds) | `StarterPlayer.StarterPlayerScripts.MineClient` + modules |
| In-place checkpoints (disabled copies) | `ServerStorage.Checkpoints.CP_20261109_Playable1`, `CP_20261109_Final` |
| Disk backup of every script | `scripts_20261109_final\` next to this file |

## How it plays

- 2D side-view cross-section drawn entirely in GUI frames (3D rendering is switched off). Scroll vertically; ▲/▼ jump buttons bottom-right.
- Chain: tap the tunnel → miners walk out, dig, carry ore back to the crate → tap the elevator → it drops to the **deepest floor with ore and fills on the way up** (richest ore first) → tips onto the surface pile → tap the warehouse worker → he carts it inside → **money only on delivery**.
- Ore moves as pieces; each piece is worth its shaft's value (Copper 1, Iron 10, Silver 100, Gold 1K, Ruby 10K, Diamond 100K).
- Upgrades per stage (x1 / x10 / MAX buy modes): shafts = Pickaxes, Boots, Miners (up to 5); elevator = Bigger Cage, Motor; warehouse = Bigger Cart, Sneakers.
- Managers automate exactly one stage each. Unlock the next shaft from the locked card below the last floor.
- Bottleneck legibility: crate/pile counters turn orange with "Piling up!" when ore backs up; "TAP!" bubbles on idle manual stages; panel footer bars (slowest = red); after the tutorial a "Slowest: …" chip under the money (tap it to open that stage).
- Feedback: pickaxe rock chips, floating +ore / +$ numbers, coins flying to the counter, button squash, toasts, licensed sound effects (SFX on/off bottom-left).
- Opening cinematic (~9 s, Skip always visible) → guided tutorial (Skip always visible), 14 steps: tap miner → watch → tap elevator → watch → tap warehouse → first money → open upgrades → buy Pickaxes → earn $50 → hire shaft manager → manual-vs-auto contrast → goals (elevator manager, warehouse manager, unlock Shaft 2) → done.
- Offline earnings: only when elevator + warehouse managers are hired; 50% of the managed rate, max 2 h, shown on a Welcome Back card; lastOnline is stamped at load so time can't be counted twice.

## Economy (Config)

Per level: ore ×1.06 (+1 piece) for price ×1.15; cage/cart capacity ×1.07 for price ×1.14. Boots/Motor/Sneakers ×1.26 price, capped. Unlocks (manager): Iron 250 (120), Silver 80K (40K), Gold 15M (7.5M), Ruby 300M (150M), Diamond 4B (2B). Elevator manager 100, warehouse manager 150, copper manager 50.

Simulated efficient player (greedy best-value buys, saving for a shaft once it costs ≤ 3 min of income): shafts 2–6 at ~8, 13, 23, 37, 54 min; income ~1.4B/s at 3 h (plateau after shaft 6). Real players will be slower.

## Tested (Studio, solo, memory saves)

- Full manual chain (mine → elevator → pile → warehouse → $10) with real UI clicks.
- Buying (x1, x10, MAX), "Need $X more" + shake when short, managers for all three stages, automation running unattended, unlocking shafts 2–6, 6 shafts × 5 miners at late-game numbers ($T), no console errors.
- Whole tutorial with real clicks and no test money: join → Shaft 2 unlocked in ~6.6 min; completion saved.
- Cinematic frames (slowed with a Studio-only `CineSpeed` attribute, now removed).
- Phone layout at 844×390 (Studio-only `FakeViewport`/`FakeTouch` attributes, now removed): world fits width, tap targets ~34–48 px, panel scrolls.
- Save/rejoin via the Studio debug hook: data stored on leave (in-transit ore returned to piles), mid-tutorial step stored, offline earnings 45 min → $6.97M and 3 h → capped at 2 h, Welcome Back card shown.
- Measured income matched the formula within 1% ($27.5/s vs $27.8/s).

## Not verified

- Real DataStore saving (Studio API access is off, so saves were in memory). Enable "Studio Access to API Services" or test in a published private server.
- A real leave/rejoin (new player instance) resuming the tutorial; tested only through the debug hook.
- Real phone/tablet touch (incl. drag-scrolling over tap areas) — only emulated sizes.
- Sounds were loaded, not listened to.
- Two players in one server (each gets their own mine GUI; nothing is shared — should be fine, untested).

## Studio-only test hook

`ServerStorage.MineDebug` (BindableFunction, created only in Studio): `dump`, `set(nil, {money=…, shafts=…})`, `stored`, `leave`, `age(nil, seconds)`, `join`, `wipe`. Put a short wait between `leave` and `join`, or the client never sees MineReady change.

## Next steps

1. Ctrl+S. 2. Turn on Studio API access and test real saves/rejoin. 3. Play on a phone. 4. Content past shaft 6 (prestige or a second mine) — income plateaus there.
