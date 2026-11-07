class_name TitleScreen
extends Control
## First screen. With no character, the player picks a class, and that choice is permanent.
## With a character, it shows their progress and opens the shop.

signal start_match

const BG := Color(0.07, 0.05, 0.11)
const ACCENT := Color(1.0, 0.85, 0.45)
const MUTED := Color(0.72, 0.70, 0.80)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := _label(box, "Cauldron Row", 60, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label(box, "A night-market potion strategy game  -  prototype 0.1", 16, MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if Profile.has_character():
		_build_returning(box)
	else:
		_build_class_pick(box)


# --- New character: permanent class choice ---------------------------------------

func _build_class_pick(box: VBoxContainer) -> void:
	var prompt := _label(box, "Choose your class. This choice is permanent.", 22, Color.WHITE)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _label(box, "You'll level up and unlock a specialization path, but you can never switch class.",
			14, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	for cid in GameData.class_ids():
		grid.add_child(_class_card(cid))


func _class_card(cid: String) -> Control:
	var d: Dictionary = GameData.CLASSES[cid]
	var color: Color = d["color"]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	card.add_theme_stylebox_override("panel", _card_style(color))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	_label(v, d["name"], 24, color.lightened(0.3))
	_label(v, d["role"], 13, ACCENT)
	_wrapped(v, "Familiars: %s (%s)" % [d["familiar"], d["familiar_desc"]], 12, Color.WHITE)
	_wrapped(v, "Passive - %s: %s" % [d["passive_name"], d["passive_desc"]], 12, MUTED)
	_wrapped(v, "Ultimate - %s: %s" % [d["ult_name"], d["ult_desc"]], 12, MUTED)
	_wrapped(v, "Signature potion: %s" % GameData.potion_name(d["signature"]), 12, MUTED)
	var paths: Array = d["paths"]
	_wrapped(v, "Paths at level %d: %s or %s" % [GameData.PATH_LEVEL, paths[0], paths[1]], 12, MUTED)

	var pick := Button.new()
	pick.text = "Become a %s" % d["name"]
	pick.custom_minimum_size = Vector2(0, 34)
	pick.pressed.connect(_confirm_class.bind(cid))
	v.add_child(pick)
	return card


func _confirm_class(cid: String) -> void:
	var cname: String = GameData.CLASSES[cid]["name"]
	var dialog := ConfirmationDialog.new()
	dialog.title = "This choice is permanent"
	dialog.dialog_text = ("Become a %s for good?\n\nYour class is locked for the life of this character. " +
			"You'll grow stronger and choose a path later, but you can't switch.") % cname
	dialog.dialog_autowrap = true
	dialog.ok_button_text = "Become a %s" % cname
	dialog.cancel_button_text = "Let me think"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		Profile.choose_class(cid)
		_build()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(480, 220))


# --- Returning character -----------------------------------------------------------

func _build_returning(box: VBoxContainer) -> void:
	var d := Profile.class_data()
	var color: Color = d["color"]

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 0)
	card.add_theme_stylebox_override("panel", _card_style(color))
	box.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	_label(v, "%s  -  Level %d" % [d["name"], Profile.level], 30, color.lightened(0.3))
	var need := GameData.xp_for_level(Profile.level)
	_label(v, "XP %d / %d" % [Profile.xp, need], 13, MUTED)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = need
	bar.value = Profile.xp
	bar.custom_minimum_size = Vector2(0, 10)
	v.add_child(bar)
	_label(v, "Matches %d  -  Wins %d  -  Best takings %dc" %
			[Profile.matches_played, Profile.wins, Profile.best_coins], 13, MUTED)

	var paths: Array = d["paths"]
	if Profile.level >= GameData.PATH_LEVEL:
		_wrapped(v, "Path unlocked! Choosing between %s and %s arrives in a future build." %
				[paths[0], paths[1]], 13, ACCENT)
	else:
		_wrapped(v, "At level %d you'll choose a path: %s or %s." %
				[GameData.PATH_LEVEL, paths[0], paths[1]], 13, ACCENT)

	_wrapped(v, "Passive - %s: %s" % [d["passive_name"], d["passive_desc"]], 12, MUTED)
	_wrapped(v, "Ultimate - %s: %s" % [d["ult_name"], d["ult_desc"]], 12, MUTED)

	var play := Button.new()
	play.text = "Open the shop"
	play.add_theme_font_size_override("font_size", 22)
	play.custom_minimum_size = Vector2(0, 52)
	play.pressed.connect(func() -> void: start_match.emit())
	box.add_child(play)

	var how := _wrapped(box, "Each match is 3 days. By day, send familiars into the woods for ingredients " +
			"and brew potions. At night the market opens: price your stock, beat the rival shop, " +
			"and pull your familiars back before the Gloomlings get them. Most coins wins.", 13, MUTED)
	how.custom_minimum_size = Vector2(560, 0)

	var abandon := Button.new()
	abandon.text = "Abandon character..."
	abandon.flat = true
	abandon.add_theme_color_override("font_color", Color(0.85, 0.45, 0.45))
	abandon.pressed.connect(_confirm_abandon)
	box.add_child(abandon)


func _confirm_abandon() -> void:
	var cname: String = Profile.class_data()["name"]
	var dialog := ConfirmationDialog.new()
	dialog.title = "Abandon character?"
	dialog.dialog_text = ("This permanently deletes your level %d %s and all progress. " +
			"It's the only way to pick a different class.") % [Profile.level, cname]
	dialog.dialog_autowrap = true
	dialog.ok_button_text = "Delete my %s" % cname
	dialog.cancel_button_text = "Keep it"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		Profile.abandon_character()
		_build()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(480, 200))


# --- Helpers -------------------------------------------------------------------------

func _card_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.18)
	sb.border_color = color.darkened(0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	return sb


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _wrapped(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := _label(parent, text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(340, 0)
	return l
