extends Node
## Root of the game. Swaps between the title screen, a match, and the results screen.

var _current: Node = null


func _ready() -> void:
	randomize()
	show_title()


func show_title() -> void:
	get_tree().paused = false
	var title := TitleScreen.new()
	title.start_match.connect(start_match)
	_swap(title)


func start_match() -> void:
	if not Profile.has_character():
		show_title()
		return
	var world := MatchWorld.new()
	world.setup(Profile.class_id, _pick_rival_class())
	world.match_finished.connect(_on_match_finished)
	world.quit_to_title.connect(show_title)
	_swap(world)


func _on_match_finished(summary: Dictionary) -> void:
	var progress := Profile.add_match_result(int(summary["player_coins"]), bool(summary["won"]))
	var results := ResultsScreen.new()
	results.setup(summary, progress)
	results.continue_pressed.connect(show_title)
	_swap(results)


func _pick_rival_class() -> String:
	var ids := GameData.class_ids()
	ids.erase(Profile.class_id)
	return ids.pick_random()


func _swap(node: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = node
	add_child(node)
