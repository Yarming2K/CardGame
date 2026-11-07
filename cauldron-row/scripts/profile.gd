extends Node
## Autoload "Profile": the player's persistent character.
## The class is chosen once and locked; only abandoning the character clears it.

const SAVE_PATH := "user://profile.json"

var class_id: String = ""
var level: int = 1
var xp: int = 0
var matches_played: int = 0
var wins: int = 0
var best_coins: int = 0
var lifetime_coins: int = 0


func _ready() -> void:
	load_profile()


func has_character() -> bool:
	return class_id != ""


func class_data() -> Dictionary:
	return GameData.CLASSES[class_id]


func choose_class(id: String) -> void:
	if has_character():
		push_warning("Class is already locked to %s." % class_id)
		return
	if not GameData.CLASSES.has(id):
		push_error("Unknown class: %s" % id)
		return
	class_id = id
	save_profile()


## Records a finished match and returns {"xp": gained, "levels": levels_gained}.
func add_match_result(coins: int, won: bool) -> Dictionary:
	matches_played += 1
	if won:
		wins += 1
	best_coins = maxi(best_coins, coins)
	lifetime_coins += coins
	var gained: int = coins + (GameData.WIN_XP_BONUS if won else GameData.LOSS_XP_BONUS)
	xp += gained
	var levels_gained := 0
	while xp >= GameData.xp_for_level(level):
		xp -= GameData.xp_for_level(level)
		level += 1
		levels_gained += 1
	save_profile()
	return {"xp": gained, "levels": levels_gained}


## Deletes the character entirely. This is the only way to change class.
func abandon_character() -> void:
	class_id = ""
	level = 1
	xp = 0
	matches_played = 0
	wins = 0
	best_coins = 0
	lifetime_coins = 0
	save_profile()


func to_dict() -> Dictionary:
	return {
		"version": 1,
		"class_id": class_id,
		"level": level,
		"xp": xp,
		"matches_played": matches_played,
		"wins": wins,
		"best_coins": best_coins,
		"lifetime_coins": lifetime_coins,
	}


func save_profile() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not save profile: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(to_dict(), "  "))


func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Profile save is unreadable; starting fresh.")
		return
	var d: Dictionary = data
	class_id = str(d.get("class_id", ""))
	if class_id != "" and not GameData.CLASSES.has(class_id):
		class_id = ""
	level = maxi(1, int(d.get("level", 1)))
	xp = maxi(0, int(d.get("xp", 0)))
	matches_played = int(d.get("matches_played", 0))
	wins = int(d.get("wins", 0))
	best_coins = int(d.get("best_coins", 0))
	lifetime_coins = int(d.get("lifetime_coins", 0))
