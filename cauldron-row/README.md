# Cauldron Row (prototype 0.1)

A night-market potion strategy game with a light RTS layer. Run a potion shop, send familiars into the woods for ingredients, brew, and out-sell a rival shop over three days and nights. Your class is permanent.

See [DESIGN.md](DESIGN.md) for the full design and roadmap.

## Running it

1. Install **Godot 4.4 or newer** (standard version, not .NET) from godotengine.org.
2. In the Godot Project Manager, click **Import** and select `cauldron-row/project.godot`.
3. Press **F5** (or the Play button).

> **Status:** this build was written without access to a running copy of Godot, so it has only been syntax-checked, not play-tested. If anything errors on first launch, copy the message from Godot's **Output** or **Debugger** panel and it can be fixed quickly.

## How to play

- **First launch:** choose your class. This is permanent for the character.
- **Day:** select familiars and right-click a grove to start them gathering. Click recipes (or press 1-6) to brew. Nightshade only grows in the rich groves in the deep woods.
- **Night:** shoppers walk Market Row. Each buys from the cheapest shop that has what they want, and reputation breaks ties. Adjust prices live with **-** and **+**. Gloomlings hunt in the woods, so press **R** to recall your familiars.
- **Dawn:** half of your unsold potions spoil, and your ultimate recharges.
- After 3 nights, the player with the most coins wins. You earn XP either way.

### Controls

| Input | Action |
|---|---|
| Left-click / drag | Select familiars (Shift adds to selection) |
| Right-click grove | Gather there (they loop on their own) |
| Right-click your shop | Send selected familiars home |
| Right-click ground | Move there |
| A | Select all familiars |
| R | Recall selected (or all) familiars |
| Q | Use your ultimate |
| 1-6 | Brew recipe 1-6 |
| Esc | Pause / cancel targeting |

## What's in 0.1

- Permanent class choice with a confirmation step, saved to `user://profile.json`
- All 6 classes with their own familiars, passives, ultimates and signature potions
- Gathering with auto-looping familiars, contested rich groves, and regrowth
- Brew queue, live per-potion pricing, customers who compare price and reputation
- Day/night cycle with Gloomlings, knockouts, and Market Row as a safe zone
- An AI rival (random class) that gathers, brews, undercuts your prices, recalls at night, and uses its ultimate
- XP and levels across matches (paths are announced at level 5 and arrive in 0.3)

## Code map

| File | What it does |
|---|---|
| `scripts/game_data.gd` | All tuning numbers, potions, and classes. Start here to rebalance |
| `scripts/profile.gd` | Autoload: the persistent character (class lock, level, XP) |
| `scripts/main.gd` | Switches between title, match, and results screens |
| `scripts/match_world.gd` | One match: clock, rules, spawning, player input, drawing the map |
| `scripts/shop.gd` | A shop's stock, cauldron, prices, and drawing |
| `scripts/familiar.gd` | Worker unit state machine |
| `scripts/grove.gd`, `gloomling.gd`, `customer.gd` | Map entities |
| `scripts/rival_ai.gd` | The AI shopkeeper (reused later for bots in PvP) |
| `scripts/hud.gd` | In-match side panel, banners, pause menu |
| `scripts/title_screen.gd`, `results_screen.gd` | Menus |

Everything is drawn with simple shapes in code, so there are no art assets yet.
