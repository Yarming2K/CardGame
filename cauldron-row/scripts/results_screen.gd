class_name ResultsScreen
extends Control
## End-of-match summary: who earned more, XP gained, and level-ups.

signal continue_pressed

const ACCENT := Color(1.0, 0.85, 0.45)
const MUTED := Color(0.72, 0.70, 0.80)

var summary: Dictionary = {}
var progress: Dictionary = {}


func setup(p_summary: Dictionary, p_progress: Dictionary) -> void:
	summary = p_summary
	progress = p_progress


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(560, 0)
	center.add_child(box)

	var won: bool = summary.get("won", false)
	var tied: bool = summary.get("tied", false)
	var headline := "Victory!"
	if tied:
		headline = "A dead heat"
	elif not won:
		headline = "The rival out-earned you"
	_label(box, headline, 48, ACCENT if won else Color(0.85, 0.75, 0.95))

	var rival_name: String = summary.get("rival_name", "The rival")
	_label(box, "Your takings: %dc  (%d potions sold, reputation %d)" % [
		int(summary.get("player_coins", 0)), int(summary.get("player_sold", 0)),
		int(summary.get("player_rep", 0))], 18, Color.WHITE)
	_label(box, "%s: %dc  (%d potions sold, reputation %d)" % [
		rival_name, int(summary.get("rival_coins", 0)), int(summary.get("rival_sold", 0)),
		int(summary.get("rival_rep", 0))], 18, MUTED)
	_label(box, "Shoppers who left empty-handed: %d" % int(summary.get("missed", 0)), 14, MUTED)

	box.add_child(HSeparator.new())

	var cname: String = Profile.class_data()["name"]
	_label(box, "+%d XP" % int(progress.get("xp", 0)), 26, ACCENT)
	var levels: int = progress.get("levels", 0)
	if levels > 0:
		_label(box, "Level up! Your %s is now level %d." % [cname, Profile.level], 20, Color(0.6, 1.0, 0.6))
	_label(box, "Level %d  -  XP %d / %d" % [Profile.level, Profile.xp,
			GameData.xp_for_level(Profile.level)], 14, MUTED)

	var cont := Button.new()
	cont.text = "Continue"
	cont.add_theme_font_size_override("font_size", 20)
	cont.custom_minimum_size = Vector2(0, 46)
	cont.pressed.connect(func() -> void: continue_pressed.emit())
	box.add_child(cont)


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
