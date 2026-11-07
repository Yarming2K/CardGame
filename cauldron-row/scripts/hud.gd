class_name Hud
extends CanvasLayer
## In-match interface: the side panel (clock, ultimate, ingredients, cauldron,
## live prices, forecast, familiars, log), the phase banner, the Seer's
## prophecy picker, and the pause menu. Built entirely in code.

const PANEL_X := 1200.0
const PANEL_W := 400.0
const SCREEN_H := 900.0
const MUTED := Color(0.72, 0.70, 0.80)
const ACCENT := Color(1.0, 0.85, 0.45)

var world: MatchWorld
var shop: Shop

var _phase_label: Label
var _phase_bar: ProgressBar
var _coins_label: Label
var _rival_label: Label
var _ult_button: Button
var _ing_labels: Array[Label] = []
var _transmute_buttons: Array[Button] = []
var _brew_label: Label
var _brew_bar: ProgressBar
var _queue_label: Label
var _recipe_buttons: Dictionary = {}
var _stock_labels: Dictionary = {}
var _price_labels: Dictionary = {}
var _rival_price_labels: Dictionary = {}
var _forecast_label: Label
var _familiar_label: Label
var _log_label: Label
var _hint_label: Label
var _banner: Control
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _prophecy_panel: PanelContainer
var _pause_layer: Control


func setup(p_world: MatchWorld) -> void:
	world = p_world
	shop = world.player_shop


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_panel(root)
	_build_hint(root)
	_build_banner(root)
	_build_prophecy_picker(root)
	_build_pause_menu(root)


# --- Building ------------------------------------------------------------------

func _build_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(PANEL_X, 0)
	panel.size = Vector2(PANEL_W, SCREEN_H)
	panel.add_theme_stylebox_override("panel", _style(Color(0.09, 0.065, 0.13, 0.98), 0, 12))
	root.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 5)
	scroll.add_child(box)

	var d := shop.data()

	# Clock and score.
	_phase_label = _label(box, "", 20, ACCENT)
	_phase_bar = ProgressBar.new()
	_phase_bar.show_percentage = false
	_phase_bar.custom_minimum_size = Vector2(0, 8)
	box.add_child(_phase_bar)
	_coins_label = _label(box, "", 17)
	_rival_label = _label(box, "", 12, MUTED)

	# Ultimate.
	_section(box, "%s  -  %s" % [d["name"], d["passive_name"]])
	_wrapped(box, d["passive_desc"], 12, MUTED)
	_ult_button = Button.new()
	_ult_button.add_theme_font_size_override("font_size", 14)
	_ult_button.tooltip_text = d["ult_desc"]
	_ult_button.pressed.connect(world.player_use_ult)
	box.add_child(_ult_button)
	_wrapped(box, d["ult_desc"], 12, MUTED)

	# Ingredients.
	_section(box, "Ingredients")
	var alchemist := shop.class_id == "alchemist"
	var grid := GridContainer.new()
	grid.columns = 3 if alchemist else 2
	grid.add_theme_constant_override("h_separation", 10)
	box.add_child(grid)
	for i in GameData.ING_COUNT:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_swatch(GameData.ING_COLORS[i]))
		_label(row, GameData.ING_NAMES[i], 13)
		grid.add_child(row)
		_ing_labels.append(_label(grid, "0", 14))
		if alchemist:
			var b := _small_button("+1", "Transmute: turn 2 of your most-stocked ingredient into 1 %s"
					% GameData.ING_NAMES[i])
			b.pressed.connect(_on_transmute.bind(i))
			grid.add_child(b)
			_transmute_buttons.append(b)

	# Cauldron.
	_section(box, "Cauldron")
	_brew_label = _label(box, "", 13)
	_brew_bar = ProgressBar.new()
	_brew_bar.show_percentage = false
	_brew_bar.custom_minimum_size = Vector2(0, 8)
	box.add_child(_brew_bar)
	_queue_label = _label(box, "", 11, MUTED)
	var rgrid := GridContainer.new()
	rgrid.columns = 2
	box.add_child(rgrid)
	var recipes := shop.recipes()
	for i in recipes.size():
		var pid: String = recipes[i]
		var b := Button.new()
		b.text = "[%d] %s\n%s" % [i + 1, GameData.potion_name(pid), GameData.cost_text(pid)]
		b.tooltip_text = "Brew time %.1fs - base value %dc" % [shop.brew_time(pid),
				int(GameData.POTIONS[pid]["value"])]
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_color", GameData.potion_color(pid).lightened(0.3))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_brew.bind(pid))
		rgrid.add_child(b)
		_recipe_buttons[pid] = b

	# Stock and live prices.
	_section(box, "Stock & prices (change any time)")
	var pgrid := GridContainer.new()
	pgrid.columns = 6
	pgrid.add_theme_constant_override("h_separation", 6)
	box.add_child(pgrid)
	for h in ["Potion", "Have", "", "Price", "", "Rival"]:
		_label(pgrid, h, 11, MUTED)
	for pid in recipes:
		_label(pgrid, GameData.potion_name(pid), 12, GameData.potion_color(pid).lightened(0.2))
		_stock_labels[pid] = _label(pgrid, "0", 13)
		var minus := _small_button("-", "Lower price")
		minus.pressed.connect(_on_price.bind(pid, -1))
		pgrid.add_child(minus)
		_price_labels[pid] = _label(pgrid, "", 13, ACCENT)
		var plus := _small_button("+", "Raise price")
		plus.pressed.connect(_on_price.bind(pid, 1))
		pgrid.add_child(plus)
		_rival_price_labels[pid] = _label(pgrid, "", 11, MUTED)

	# Forecast.
	_section(box, "Tonight's demand")
	_forecast_label = _wrapped(box, "", 12)

	# Familiars.
	_section(box, "Your %s" % d["familiar"])
	_familiar_label = _wrapped(box, "", 12)
	var fbox := HBoxContainer.new()
	box.add_child(fbox)
	var sel_all := _small_button("Select all (A)", "Select every familiar")
	sel_all.pressed.connect(world.select_all)
	fbox.add_child(sel_all)
	var recall := _small_button("Recall (R)", "Bring selected (or all) familiars home")
	recall.pressed.connect(world.recall_familiars)
	fbox.add_child(recall)

	# Log.
	_section(box, "Market log")
	_log_label = _wrapped(box, "", 11, MUTED)

	# Controls.
	_section(box, "Controls")
	_wrapped(box, "Left-click or drag: select familiars (Shift adds)\n" +
			"Right-click a grove: gather there\n" +
			"Right-click your shop: send them home\n" +
			"Right-click ground: move there\n" +
			"A select all  -  R recall  -  Q ultimate\n" +
			"1-6 brew a recipe  -  Esc pause", 11, MUTED)


func _build_hint(root: Control) -> void:
	_hint_label = Label.new()
	_hint_label.position = Vector2(0, 12)
	_hint_label.size = Vector2(PANEL_X, 30)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint_label.add_theme_constant_override("outline_size", 5)
	_hint_label.text = "Click a grove to Blight it  (right-click or Esc to cancel)"
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.visible = false
	root.add_child(_hint_label)


func _build_banner(root: Control) -> void:
	_banner = VBoxContainer.new()
	_banner.position = Vector2(0, 330)
	_banner.size = Vector2(PANEL_X, 120)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner)
	_banner_title = _outlined(_banner, 54, ACCENT)
	_banner_sub = _outlined(_banner, 20, Color.WHITE)
	_banner.visible = false


func _build_prophecy_picker(root: Control) -> void:
	_prophecy_panel = PanelContainer.new()
	_prophecy_panel.position = Vector2(PANEL_X / 2.0 - 170.0, 250)
	_prophecy_panel.custom_minimum_size = Vector2(340, 0)
	_prophecy_panel.add_theme_stylebox_override("panel", _style(Color(0.12, 0.09, 0.2, 0.97), 10, 16))
	_prophecy_panel.visible = false
	root.add_child(_prophecy_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_prophecy_panel.add_child(box)
	_label(box, "Prophecy: choose tonight's favored potion", 15, ACCENT)
	_wrapped(box, "3x as many shoppers will want it, and they'll pay up to 50% more.", 12, MUTED)
	for pid in GameData.BASIC_POTIONS:
		var b := Button.new()
		b.text = GameData.potion_name(pid)
		b.add_theme_color_override("font_color", GameData.potion_color(pid).lightened(0.3))
		b.pressed.connect(_on_prophecy.bind(pid))
		box.add_child(b)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: _prophecy_panel.visible = false)
	box.add_child(cancel)


func _build_pause_menu(root: Control) -> void:
	_pause_layer = ColorRect.new()
	(_pause_layer as ColorRect).color = Color(0, 0, 0, 0.6)
	_pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.visible = false
	root.add_child(_pause_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.12, 0.09, 0.2, 0.98), 10, 24))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := _label(box, "Paused", 32, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var resume := Button.new()
	resume.text = "Resume (Esc)"
	resume.custom_minimum_size = Vector2(260, 40)
	resume.pressed.connect(toggle_pause)
	box.add_child(resume)
	var quit := Button.new()
	quit.text = "Abandon match (no XP)"
	quit.custom_minimum_size = Vector2(260, 40)
	quit.pressed.connect(_on_abandon)
	box.add_child(quit)


# --- Public ----------------------------------------------------------------------

func show_banner(title: String, sub: String) -> void:
	_banner_title.text = title
	_banner_sub.text = sub
	_banner.visible = true
	_banner.modulate.a = 1.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.8)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.9)
	_banner_tween.tween_callback(func() -> void: _banner.visible = false)


func open_prophecy_picker() -> void:
	_prophecy_panel.visible = true


func toggle_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_pause_layer.visible = paused


# --- Input -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	if world.targeting_blight:
		world.targeting_blight = false
	elif _prophecy_panel.visible:
		_prophecy_panel.visible = false
	elif not world.finished:
		toggle_pause()
	get_viewport().set_input_as_handled()


func _on_brew(pid: String) -> void:
	shop.start_brew(pid)


func _on_price(pid: String, change: int) -> void:
	shop.set_price(pid, shop.price_of(pid) + change)


func _on_transmute(ing: int) -> void:
	shop.transmute(ing)


func _on_prophecy(pid: String) -> void:
	_prophecy_panel.visible = false
	world.activate_ult(shop, pid)


func _on_abandon() -> void:
	get_tree().paused = false
	world.quit_to_title.emit()


# --- Per-frame refresh -----------------------------------------------------------

func _process(_delta: float) -> void:
	if world == null or world.finished:
		return
	var d := shop.data()
	var rival := world.rival_shop

	var phase := "Night" if world.is_night else "Day"
	_phase_label.text = "%s %d of %d" % [phase, world.day, GameData.DAYS]
	var total := GameData.NIGHT_LENGTH if world.is_night else GameData.DAY_LENGTH
	_phase_bar.max_value = total
	_phase_bar.value = total - world.phase_left
	_coins_label.text = "Coins %d     Reputation %d" % [shop.coins, shop.reputation]
	_rival_label.text = "Rival: %s (%s)  -  %dc, rep %d" % [rival.display_name,
			rival.data()["name"], rival.coins, rival.reputation]

	# Ultimate.
	if shop.ult_active_time > 0.0:
		_ult_button.text = "%s  -  active %ds" % [d["ult_name"], ceili(shop.ult_active_time)]
	elif shop.ult_ready:
		_ult_button.text = "[Q] %s  -  ready" % d["ult_name"]
	else:
		_ult_button.text = "%s  -  used (recharges at dawn)" % d["ult_name"]
	_ult_button.disabled = not shop.ult_ready
	_hint_label.visible = world.targeting_blight

	for i in GameData.ING_COUNT:
		_ing_labels[i].text = str(shop.ingredients[i])
	for i in _transmute_buttons.size():
		_transmute_buttons[i].disabled = not shop.can_transmute(i)

	# Cauldron.
	if shop.brew_queue.is_empty():
		_brew_label.text = "Cauldron idle - pick a recipe below."
		_brew_bar.value = 0.0
	else:
		var pid: String = shop.brew_queue[0]
		_brew_label.text = "Brewing: %s" % GameData.potion_name(pid)
		_brew_bar.max_value = shop.brew_time(pid)
		_brew_bar.value = shop.brew_progress
	var queued := PackedStringArray()
	for i in range(1, shop.brew_queue.size()):
		queued.append(GameData.potion_name(shop.brew_queue[i]))
	var queue_text := "Queue %d/%d" % [shop.brew_queue.size(), GameData.MAX_QUEUE]
	if not queued.is_empty():
		queue_text += ": next " + ", ".join(queued)
	if shop.wildcard_active():
		queue_text += "  -  Philosopher's Hour: any ingredient works!"
	_queue_label.text = queue_text
	for pid in _recipe_buttons:
		var b: Button = _recipe_buttons[pid]
		b.disabled = not shop.can_brew(pid)

	# Stock and prices.
	for pid in _stock_labels:
		(_stock_labels[pid] as Label).text = str(shop.stock(pid))
		(_price_labels[pid] as Label).text = "%dc" % shop.price_of(pid)
		var rl: Label = _rival_price_labels[pid]
		if rival.knows(pid):
			rl.text = "%dc (%d)" % [rival.price_of(pid), rival.stock(pid)]
		else:
			rl.text = "-"

	_forecast_label.text = _forecast_text()
	_familiar_label.text = _familiar_text()
	_log_label.text = "\n".join(PackedStringArray(world.log_lines))


func _forecast_text() -> String:
	var lines := PackedStringArray()
	if world.favored_potion != "":
		lines.append("Prophecy: %s is favored (x3 shoppers, +50%% budget)." %
				GameData.potion_name(world.favored_potion))
	if shop.class_id == "seer":
		var ranked: Array = GameData.BASIC_POTIONS.duplicate()
		ranked.sort_custom(func(a, b): return world.demand_weight(a) > world.demand_weight(b))
		for pid in ranked:
			lines.append("%s  x%.1f" % [GameData.potion_name(pid), world.demand_weight(pid)])
		lines.append("(Observatory: you see the full forecast.)")
	else:
		lines.append("Rumor: shoppers are after %s." % GameData.potion_name(world.top_demand()))
		lines.append("Connoisseurs pay well for signature potions.")
	return "\n".join(lines)


func _familiar_text() -> String:
	var working := 0
	var idle := 0
	var down := 0
	var selected := 0
	for f in shop.familiars:
		if f.selected:
			selected += 1
		if f.is_down():
			down += 1
		elif f.is_working():
			working += 1
		else:
			idle += 1
	var text := "%d gathering, %d idle, %d knocked out.  %d selected." % [working, idle, down, selected]
	if world.is_night and working > 0 and not shop.familiars[0].is_immune():
		text += "\nWarning: Gloomlings hunt anything left in the woods!"
	return text


# --- Widget helpers ----------------------------------------------------------------

func _style(bg: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _label(parent: Node, text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _wrapped(parent: Node, text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := _label(parent, text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - 60.0, 0)
	return l


func _outlined(parent: Node, font_size: int, color: Color) -> Label:
	var l := _label(parent, "", font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _section(parent: Node, title: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	_label(parent, title, 14, ACCENT)


func _swatch(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(12, 12)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


func _small_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 12)
	return b
