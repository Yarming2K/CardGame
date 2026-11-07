# Cauldron Row: Design Doc

A night-market potion game with a light real-time strategy layer, built for a friend group of about 6 who want to play both in short sessions and over the long term.

## Pillars

1. **Solo first, online optional.** The full game is playable alone. Being online only adds PvP and ways to interact with other players.
2. **Your class is permanent.** You pick a class when you create a character and keep it for that character's whole life. Depth comes from levels and specialization paths, not from switching.
3. **Light RTS.** Few units, big decisions. Players need spare attention to trade and haggle with each other.
4. **Every class needs the others.** In multiplayer, classes depend on each other. In solo, AI shops fill those roles at worse rates.
5. **Short and long play.** A match takes about 10 minutes in the prototype (about 30 in the full game). Progress across matches builds up over months.

## The six classes

| Class | Familiar (unit) | Passive | Ultimate (once per day) | Paths at level 5 |
|---|---|---|---|---|
| Herbalist | Sproutlings: fast, fragile gatherers | Greenhouse: free ingredient every 8s | Overgrowth: all groves refill, 2x gathering for 20s | Gardener / Forager |
| Alchemist | Brass Golems: slow, carry 5 | Brew 25% faster, transmute 2 ingredients into 1 | Philosopher's Hour: any ingredient works for 30s | Transmuter / Golemancer |
| Apothecary | Mender Moths | +2 rep per sale, 3x faster recovery after a knockout | Panacea: revive all, immune to Gloomlings for 25s | Healer / Masterworker |
| Enchanter | Wisps | Vault: potions never spoil | Enthrall: every shopper comes to you for 20s | Charmer / Beastcaller |
| Hexer | Imps: fast raiders | 60% chance to banish a Gloomling on contact | Blight: only you can harvest a grove until dawn | Curse-weaver / Imp Lord |
| Seer | Crows: fastest fliers | Observatory: full demand forecast | Prophecy: choose tonight's favored potion | Oracle / Spymaster |

Each class also has one **signature potion** that only it can brew. Connoisseur customers pay well for these.

**Character rules:** one character per save, class locked forever. The only way to change class is to abandon the character, which deletes it. Friends may share a class; the paths keep two players of the same class distinct.

## A match

- **3 days.** Each day has a **day** phase (expand: gather and brew) and a **night** phase (the market opens and the woods get dangerous). The final night ends the match, and the player with the most coins wins.
- **Map:** Market Row runs through the center and is safe. All shops face it. The Wildwood surrounds it: small groves sit near each shop, while rich groves sit in the contested deep woods (Nightshade grows *only* there).
- **Familiars** gather on their own once assigned to a grove: walk out, harvest, carry home, repeat. A knocked-out familiar respawns at its shop. Nothing is permanently lost.
- **Gloomlings** roam the woods at night and knock out any familiar they catch. Pull your familiars back, or gamble.
- **Customers** walk Market Row. Each wants one potion and has a budget. They buy from the **cheapest** shop that has it in stock, and ties go to **reputation**. Prices can be changed live, which starts real-time price wars.
- **Demand** changes every night. Everyone hears a rumor about the top potion. The Seer sees the full forecast.
- **At dawn** half of each shop's unsold potions spoil (except the Enchanter's). Ultimates recharge.

## Planned interactions (beyond the prototype)

**Within a match:** open trading (ingredients, potions, coins, favors), **Masterworks** (two potions from different shops plus a catalyst, with reputation for every shop that contributed), big multi-shop orders, favors/IOUs, the Hexer's paid curses and the wards that protect against them, a Market Council vote each dawn, couriers to outlying customers that can be raided or escorted, and hiring other players' familiars.

**Solo:** your own market against **5 named AI shopkeepers** (one per other class), with new regions over time (Swamp, Frost Peaks, Sky Market). AI shops trade at worse prices than a friend would.

**Online, live:** PvP matches. One friend hosts, so no game server is needed. AI fills empty seats.

**Online, async (anytime):** a Trading Post, friends' shops showing up in your solo market (AI-run, but trades really reach them), lending familiars for a cut, favors that carry over, a shared Grimoire of recipe discoveries (discoverers earn royalties), and a group guild project that unlocks a region for everyone.

## Progression rules

- **Carries into PvP:** class, unlocked talents (picked as a loadout before each match), recipes, cosmetics.
- **Doesn't carry over:** coins, shop upgrades, stockpiles. Every PvP match starts even.
- Progression gives **choices, not power**, so a friend who plays 10 hours a week doesn't flatten one who plays 1.

## Tech

- Godot 4, GDScript, Compatibility renderer (exports to desktop and web).
- Built solo first. The AI rivals double as bots for empty seats.
- All tuning numbers live in `scripts/game_data.gd`.

## Roadmap

| Version | Goal |
|---|---|
| **0.1 (this build)** | Core loop vs one AI rival: permanent class pick, gather, brew, sell, day/night, Gloomlings, live prices, ultimates, XP and levels |
| 0.2 | Full market of 5 AI rivals; trading with AI shops; Masterworks; favors |
| 0.3 | Specialization paths and talents; the Grimoire (recipe discovery) |
| 0.4 | Solo campaign: regions, regulars, shop upgrades between matches |
| 0.5 | Async online: Trading Post, visiting shops, shared Grimoire, guild project |
| 0.6 | Live PvP matches (host-based), AI filling empty seats |

## Open questions

- Second character slots: allowed (each starting from zero), or strictly one character per person?
- Should fighting go further (familiars destroyed, shops raided) or stay non-lethal?
- Final match length for the full game (the prototype uses about 9 minutes; the design target is about 30).
