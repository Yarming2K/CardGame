class_name GameData
extends RefCounted
## Static game data and tuning numbers for Cauldron Row.
## Everything a designer is likely to tweak lives in this file.

enum Ing { MOONPETAL, EMBERROOT, MISTWATER, GOLDCOMB, NIGHTSHADE }

const ING_COUNT := 5
const ING_NAMES = ["Moonpetal", "Emberroot", "Mistwater", "Goldcomb", "Nightshade"]
const ING_COLORS = [
	Color(0.86, 0.90, 1.0),
	Color(0.95, 0.38, 0.22),
	Color(0.36, 0.66, 1.0),
	Color(1.0, 0.80, 0.26),
	Color(0.62, 0.34, 0.88),
]

# --- Match pacing -----------------------------------------------------------
const DAYS := 3
const DAY_LENGTH := 100.0
const NIGHT_LENGTH := 80.0
const CUSTOMER_INTERVAL_DAY := 6.0
const CUSTOMER_INTERVAL_NIGHT := 1.6
const CONNOISSEUR_CHANCE := 0.12

# --- Gathering --------------------------------------------------------------
const GATHER_TIME := 1.0
const SMALL_GROVE_MAX := 8
const SMALL_GROVE_REGROW := 5.0
const RICH_GROVE_MAX := 18
const RICH_GROVE_REGROW := 2.5

# --- Brewing ----------------------------------------------------------------
const MAX_QUEUE := 5
const GREENHOUSE_INTERVAL := 8.0

# --- Night ------------------------------------------------------------------
const KO_TIME := 12.0
const GLOOM_CHASE_RADIUS := 130.0
const GLOOM_SPEED := 50.0
const GLOOM_CHASE_SPEED := 82.0
const HEXER_BANISH_CHANCE := 0.6

# --- Shop -------------------------------------------------------------------
const START_REPUTATION := 10
const START_INGREDIENTS := 2
const SPOIL_FRACTION := 0.5
const MIN_PRICE := 1
const MAX_PRICE := 30

# --- Progression ------------------------------------------------------------
const PATH_LEVEL := 5
const WIN_XP_BONUS := 40
const LOSS_XP_BONUS := 10

# --- Potions ----------------------------------------------------------------
# cost maps ingredient (Ing value) -> amount.
const POTIONS = {
	"healing_tonic": {
		"name": "Healing Tonic",
		"cost": {Ing.MOONPETAL: 1, Ing.MISTWATER: 1},
		"value": 4, "time": 3.5, "color": Color(0.55, 0.95, 0.65),
	},
	"love_draught": {
		"name": "Love Draught",
		"cost": {Ing.GOLDCOMB: 1, Ing.MOONPETAL: 1},
		"value": 5, "time": 3.5, "color": Color(1.0, 0.55, 0.75),
	},
	"ember_elixir": {
		"name": "Ember Elixir",
		"cost": {Ing.EMBERROOT: 1, Ing.GOLDCOMB: 1},
		"value": 5, "time": 3.5, "color": Color(1.0, 0.5, 0.2),
	},
	"sleep_draught": {
		"name": "Sleep Draught",
		"cost": {Ing.MISTWATER: 1, Ing.NIGHTSHADE: 1},
		"value": 6, "time": 3.5, "color": Color(0.45, 0.55, 1.0),
	},
	"shadow_tincture": {
		"name": "Shadow Tincture",
		"cost": {Ing.NIGHTSHADE: 1, Ing.EMBERROOT: 1},
		"value": 6, "time": 3.5, "color": Color(0.7, 0.35, 0.85),
	},
	# Signature potions: only one class can brew each.
	"verdant_balm": {
		"name": "Verdant Balm",
		"cost": {Ing.MOONPETAL: 2, Ing.MISTWATER: 1},
		"value": 12, "time": 6.0, "color": Color(0.3, 0.9, 0.35),
	},
	"liquid_gold": {
		"name": "Liquid Gold",
		"cost": {Ing.GOLDCOMB: 2, Ing.EMBERROOT: 1},
		"value": 12, "time": 6.0, "color": Color(1.0, 0.85, 0.3),
	},
	"panacea_phial": {
		"name": "Panacea Phial",
		"cost": {Ing.MOONPETAL: 1, Ing.MISTWATER: 1, Ing.GOLDCOMB: 1},
		"value": 12, "time": 6.0, "color": Color(0.9, 0.9, 1.0),
	},
	"starlight_philter": {
		"name": "Starlight Philter",
		"cost": {Ing.MOONPETAL: 1, Ing.GOLDCOMB: 1, Ing.NIGHTSHADE: 1},
		"value": 12, "time": 6.0, "color": Color(0.5, 0.95, 1.0),
	},
	"hexfire_brew": {
		"name": "Hexfire Brew",
		"cost": {Ing.NIGHTSHADE: 2, Ing.EMBERROOT: 1},
		"value": 12, "time": 6.0, "color": Color(0.95, 0.25, 0.4),
	},
	"dreamsight_draught": {
		"name": "Dreamsight Draught",
		"cost": {Ing.MISTWATER: 2, Ing.NIGHTSHADE: 1},
		"value": 12, "time": 6.0, "color": Color(0.65, 0.55, 1.0),
	},
}

const BASIC_POTIONS = [
	"healing_tonic", "love_draught", "ember_elixir", "sleep_draught", "shadow_tincture",
]

# --- Classes ----------------------------------------------------------------
# A player's class is chosen once and locked for the life of the character.
const CLASSES = {
	"herbalist": {
		"name": "Herbalist",
		"color": Color(0.38, 0.78, 0.42),
		"familiar": "Sproutlings",
		"familiar_desc": "fast, fragile gatherers",
		"familiar_count": 4, "speed": 125.0, "carry": 2,
		"passive_name": "Greenhouse",
		"passive_desc": "Your shop grows a free random ingredient every 8 seconds.",
		"ult_name": "Overgrowth",
		"ult_desc": "Every grove on the map refills, and your familiars gather twice as fast for 20s.",
		"signature": "verdant_balm",
		"role": "Economy: out-gather everyone.",
		"shopkeeper": "Marigold Fen",
		"shop_name": "Marigold's Greenhouse",
		"paths": ["Gardener", "Forager"],
	},
	"alchemist": {
		"name": "Alchemist",
		"color": Color(0.88, 0.64, 0.26),
		"familiar": "Brass Golems",
		"familiar_desc": "slow, sturdy, carry a lot",
		"familiar_count": 3, "speed": 70.0, "carry": 5,
		"passive_name": "Transmutation Circle",
		"passive_desc": "Brew 25% faster, and turn 2 of your most-stocked ingredient into 1 of any other.",
		"ult_name": "Philosopher's Hour",
		"ult_desc": "For 30s, any ingredient can stand in for any other when you brew.",
		"signature": "liquid_gold",
		"role": "Production: the fastest brewer.",
		"shopkeeper": "Ignatius Brass",
		"shop_name": "Brass & Bubbles",
		"paths": ["Transmuter", "Golemancer"],
	},
	"apothecary": {
		"name": "Apothecary",
		"color": Color(0.76, 0.66, 0.96),
		"familiar": "Mender Moths",
		"familiar_desc": "quick to recover",
		"familiar_count": 3, "speed": 105.0, "carry": 3,
		"passive_name": "Bedside Manner",
		"passive_desc": "Each sale earns +2 reputation instead of +1, and knocked-out familiars recover 3x faster.",
		"ult_name": "Panacea",
		"ult_desc": "Revive every knocked-out familiar; for 25s they ignore Gloomlings.",
		"signature": "panacea_phial",
		"role": "Support: steady reputation, safe night work.",
		"shopkeeper": "Sister Wren",
		"shop_name": "Wren's Remedies",
		"paths": ["Healer", "Masterworker"],
	},
	"enchanter": {
		"name": "Enchanter",
		"color": Color(0.42, 0.86, 0.92),
		"familiar": "Wisps",
		"familiar_desc": "drifting glow-lights",
		"familiar_count": 3, "speed": 95.0, "carry": 3,
		"passive_name": "Vault",
		"passive_desc": "Your potions never spoil at dawn.",
		"ult_name": "Enthrall",
		"ult_desc": "For 20s, every shopper who wants something you stock comes to you, whatever the competition charges.",
		"signature": "starlight_philter",
		"role": "Market control: win the night rush.",
		"shopkeeper": "Lady Vesper",
		"shop_name": "Vesper's Enchantments",
		"paths": ["Charmer", "Beastcaller"],
	},
	"hexer": {
		"name": "Hexer",
		"color": Color(0.88, 0.32, 0.36),
		"familiar": "Imps",
		"familiar_desc": "fast, scrappy raiders",
		"familiar_count": 4, "speed": 120.0, "carry": 2,
		"passive_name": "Imps Fight Back",
		"passive_desc": "60% chance to banish a Gloomling that touches one of your imps.",
		"ult_name": "Blight",
		"ult_desc": "Curse a grove: only you can harvest it until dawn.",
		"signature": "hexfire_brew",
		"role": "Aggression: work the woods at night and deny groves.",
		"shopkeeper": "Grimsby Thorn",
		"shop_name": "Thorn's Hexes",
		"paths": ["Curse-weaver", "Imp Lord"],
	},
	"seer": {
		"name": "Seer",
		"color": Color(0.62, 0.52, 0.92),
		"familiar": "Crows",
		"familiar_desc": "swift fliers",
		"familiar_count": 3, "speed": 135.0, "carry": 2,
		"passive_name": "Observatory",
		"passive_desc": "See the full demand forecast for every night.",
		"ult_name": "Prophecy",
		"ult_desc": "Choose tonight's favored potion: 3x as many shoppers want it, and they'll pay up to 50% more.",
		"signature": "dreamsight_draught",
		"role": "Information: know what sells before anyone else.",
		"shopkeeper": "Madame Oriel",
		"shop_name": "Oriel's Visions",
		"paths": ["Oracle", "Spymaster"],
	},
}


static func class_ids() -> Array:
	return CLASSES.keys()


static func recipes_for(class_id: String) -> Array:
	var list: Array = BASIC_POTIONS.duplicate()
	list.append(CLASSES[class_id]["signature"])
	return list


static func potion_name(pid: String) -> String:
	return POTIONS[pid]["name"]


static func potion_color(pid: String) -> Color:
	return POTIONS[pid]["color"]


static func is_signature(pid: String) -> bool:
	return not BASIC_POTIONS.has(pid)


static func cost_text(pid: String) -> String:
	var parts := PackedStringArray()
	var cost: Dictionary = POTIONS[pid]["cost"]
	for ing in cost:
		var n: int = cost[ing]
		var ing_name: String = ING_NAMES[ing]
		if n > 1:
			parts.append("%d %s" % [n, ing_name])
		else:
			parts.append(ing_name)
	return " + ".join(parts)


static func xp_for_level(level: int) -> int:
	return 100 + (level - 1) * 50
