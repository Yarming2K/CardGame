class_name MatchWorld
extends Node2D
## One match: 3 day/night cycles on Market Row and the Wildwood around it.
## Owns the clock, all entities, player input, and the rules that connect them.
## Entities don't run their own _process; this node ticks them in a fixed order.

signal match_finished(summary: Dictionary)
signal quit_to_title

const WORLD_SIZE := Vector2(1200, 900)
const ROW_TOP := 380.0
const ROW_BOTTOM := 530.0
const LANE_Y := 505.0
const PLAYER_SHOP_POS := Vector2(380, 470)
const RIVAL_SHOP_POS := Vector2(820, 470)
const NIGHT_TINT := Color(0.48, 0.5, 0.82)
const MAX_LOG_LINES := 7

var player_class: String = ""
var rival_class: String = ""
var player_shop: Shop
var rival_shop: Shop
var shops: Array[Shop] = []
var groves: Array[Grove] = []
var familiars: Array[Familiar] = []
var customers: Array[Customer] = []
var gloomlings: Array[Gloomling] = []
var float_texts: Array[FloatText] = []
var rival_ai: RivalAI
var hud: Hud

var day: int = 1
var is_night: bool = false
var phase_left: float = 0.0
var demand: Dictionary = {}  # basic potion id -> weight for tonight
var favored_potion: String = ""
var finished: bool = false
var customers_missed: int = 0
var log_lines: Array[String] = []
var targeting_blight: bool = false

var _customer_acc: float = 0.0
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _overlay: Node2D
var _tint: CanvasModulate
var _trees: Array = []
var _cobbles: Array = []


func setup(p_player_class: String, p_rival_class: String) -> void:
	player_class = p_player_class
	rival_class = p_rival_class


func _ready() -> void:
	_tint = CanvasModulate.new()
	add_child(_tint)
	_build_decor()
	_build_groves()
	player_shop = _make_shop(player_class, true, PLAYER_SHOP_POS)
	rival_shop = _make_shop(rival_class, false, RIVAL_SHOP_POS)
	rival_ai = RivalAI.new(self, rival_shop)

	_overlay = Node2D.new()
	_overlay.z_index = 50
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)

	hud = Hud.new()
	hud.setup(self)
	add_child(hud)

	_start_day(true)


# --- Construction ------------------------------------------------------------

func _build_groves() -> void:
	var moon := GameData.Ing.MOONPETAL
	var ember := GameData.Ing.EMBERROOT
	var mist := GameData.Ing.MISTWATER
	var gold := GameData.Ing.GOLDCOMB
	var shade := GameData.Ing.NIGHTSHADE
	var layout := [
		# Small groves near each shop.
		[moon, false, Vector2(270, 290)],
		[ember, false, Vector2(490, 290)],
		[mist, false, Vector2(270, 625)],
		[gold, false, Vector2(490, 625)],
		[moon, false, Vector2(930, 290)],
		[ember, false, Vector2(710, 290)],
		[mist, false, Vector2(930, 625)],
		[gold, false, Vector2(710, 625)],
		# Rich, contested groves out in the deep woods.
		[shade, true, Vector2(600, 115)],
		[shade, true, Vector2(600, 795)],
		[ember, true, Vector2(90, 95)],
		[ember, true, Vector2(1110, 95)],
		[gold, true, Vector2(90, 815)],
		[gold, true, Vector2(1110, 815)],
	]
	for entry in layout:
		var g := Grove.new()
		var pos: Vector2 = entry[2]
		g.setup(int(entry[0]), bool(entry[1]), pos)
		add_child(g)
		groves.append(g)


func _make_shop(cid: String, player: bool, pos: Vector2) -> Shop:
	var s := Shop.new()
	s.setup(self, cid, player, pos)
	s.z_index = 1
	add_child(s)
	shops.append(s)
	var count: int = GameData.CLASSES[cid]["familiar_count"]
	for i in count:
		var f := Familiar.new()
		f.setup(s, self, i)
		f.z_index = 3
		add_child(f)
		s.familiars.append(f)
		familiars.append(f)
	return s


func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 170:
		var p := Vector2(rng.randf_range(0, WORLD_SIZE.x), rng.randf_range(0, WORLD_SIZE.y))
		if p.y > ROW_TOP - 25.0 and p.y < ROW_BOTTOM + 15.0:
			continue
		var shade := rng.randf_range(0.0, 0.08)
		_trees.append({
			"pos": p,
			"r": rng.randf_range(9.0, 20.0),
			"color": Color(0.11 + shade, 0.25 + shade * 1.5, 0.15 + shade),
		})
	for i in 260:
		var p := Vector2(rng.randf_range(0, WORLD_SIZE.x), rng.randf_range(ROW_TOP + 4.0, ROW_BOTTOM - 8.0))
		var v := rng.randf_range(-0.04, 0.04)
		_cobbles.append({"pos": p, "color": Color(0.42 + v, 0.37 + v, 0.33 + v)})


# --- Clock -------------------------------------------------------------------

func _advance_clock(delta: float) -> void:
	phase_left -= delta
	if phase_left > 0.0:
		return
	if not is_night:
		_start_night()
	elif day >= GameData.DAYS:
		_finish_match()
	else:
		day += 1
		_start_day(false)


func _start_day(first: bool) -> void:
	is_night = false
	phase_left = GameData.DAY_LENGTH
	_customer_acc = 0.0
	for gl in gloomlings:
		gl.queue_free()
	gloomlings.clear()
	for g in groves:
		g.blighted_by = null
	favored_potion = ""
	if not first:
		for s in shops:
			var lost := s.spoil_potions()
			if s.is_player and lost > 0:
				log_event("Dawn: %d of your unsold potions spoiled." % lost)
	for s in shops:
		s.ult_ready = true
	_roll_demand()
	log_event("Day %d. Gather and brew! Rumor says tonight's shoppers want %s." %
			[day, GameData.potion_name(top_demand())])
	if first:
		log_event("Tip: drag a box around your familiars, then right-click a grove to send them gathering.")
	hud.show_banner("Day %d" % day, "Gather ingredients and brew for tonight")
	rival_ai.on_phase_change()
	queue_redraw()


func _start_night() -> void:
	is_night = true
	phase_left = GameData.NIGHT_LENGTH
	_customer_acc = GameData.CUSTOMER_INTERVAL_NIGHT
	var per_side := 2 + day
	for side in [-1, 1]:
		for i in per_side:
			_spawn_gloomling(side)
	log_event("Night falls and the market opens! Gloomlings stir in the woods. Press R to recall familiars.")
	hud.show_banner("Night %d" % day, "The market is open. Beware the woods.")
	rival_ai.on_phase_change()
	queue_redraw()


func _finish_match() -> void:
	finished = true
	targeting_blight = false
	var summary := {
		"player_class": player_class,
		"rival_class": rival_class,
		"rival_name": rival_shop.display_name,
		"player_coins": player_shop.coins,
		"rival_coins": rival_shop.coins,
		"player_sold": player_shop.potions_sold,
		"rival_sold": rival_shop.potions_sold,
		"player_rep": player_shop.reputation,
		"rival_rep": rival_shop.reputation,
		"won": player_shop.coins > rival_shop.coins,
		"tied": player_shop.coins == rival_shop.coins,
		"missed": customers_missed,
	}
	match_finished.emit(summary)


# --- Demand ------------------------------------------------------------------

func _roll_demand() -> void:
	demand.clear()
	for pid in GameData.BASIC_POTIONS:
		demand[pid] = randf_range(0.4, 2.0)


func demand_weight(pid: String) -> float:
	var w: float = demand.get(pid, 0.0)
	if pid == favored_potion:
		w *= 3.0
	return w


func top_demand() -> String:
	var best: String = GameData.BASIC_POTIONS[0]
	for pid in GameData.BASIC_POTIONS:
		if demand_weight(pid) > demand_weight(best):
			best = pid
	return best


func _pick_basic() -> String:
	var total := 0.0
	for pid in GameData.BASIC_POTIONS:
		total += demand_weight(pid)
	var r := randf() * total
	for pid in GameData.BASIC_POTIONS:
		r -= demand_weight(pid)
		if r <= 0.0:
			return pid
	return GameData.BASIC_POTIONS[0]


func _pick_signature() -> String:
	var options: Array = []
	for s in shops:
		options.append(s.data()["signature"])
	return options.pick_random()


# --- Main loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	_advance_clock(delta)
	if finished:
		return
	for g in groves:
		g.tick(delta)
	for s in shops:
		s.tick(delta)
	for f in familiars:
		f.tick(delta)
	for gl in gloomlings:
		gl.tick(delta)
	_tick_customers(delta)
	rival_ai.tick(delta)
	_tick_float_texts(delta)
	_cleanup()
	_update_tint()
	# A drag that ends over the HUD never reaches _unhandled_input; finish it here.
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
		_finish_selection(_clamp_to_world(get_global_mouse_position()), Input.is_key_pressed(KEY_SHIFT))
	_overlay.queue_redraw()


func _tick_customers(delta: float) -> void:
	_customer_acc += delta
	var interval := GameData.CUSTOMER_INTERVAL_NIGHT if is_night else GameData.CUSTOMER_INTERVAL_DAY
	if _customer_acc >= interval:
		_customer_acc -= interval
		_spawn_customer()
	for i in range(customers.size() - 1, -1, -1):
		var c := customers[i]
		c.tick(delta)
		if c.done:
			if c.mood != Customer.Mood.HAPPY:
				customers_missed += 1
			c.queue_free()
			customers.remove_at(i)


func _tick_float_texts(delta: float) -> void:
	for i in range(float_texts.size() - 1, -1, -1):
		var ft := float_texts[i]
		if ft.tick(delta):
			ft.queue_free()
			float_texts.remove_at(i)


func _cleanup() -> void:
	for i in range(gloomlings.size() - 1, -1, -1):
		if gloomlings[i].dead:
			gloomlings[i].queue_free()
			gloomlings.remove_at(i)


func _update_tint() -> void:
	var t := 0.0
	if is_night:
		t = 1.0
		if day < GameData.DAYS and phase_left < 8.0:
			t = phase_left / 8.0
	elif phase_left < 10.0:
		t = 1.0 - phase_left / 10.0
	_tint.color = Color.WHITE.lerp(NIGHT_TINT, t)


# --- Spawning ----------------------------------------------------------------

func _spawn_customer() -> void:
	var conn := randf() < GameData.CONNOISSEUR_CHANCE
	var wants := _pick_signature() if conn else _pick_basic()
	var value: int = GameData.POTIONS[wants]["value"]
	var mult := randf_range(1.0, 1.6)
	if wants == favored_potion:
		mult *= 1.5
	var c := Customer.new()
	c.setup(self, wants, int(ceil(value * mult)), randf() < 0.5, conn)
	c.z_index = 2
	add_child(c)
	customers.append(c)


func _spawn_gloomling(side: int) -> void:
	var g := Gloomling.new()
	var y := 40.0 if side < 0 else WORLD_SIZE.y - 40.0
	g.setup(self, side, Vector2(randf_range(40.0, WORLD_SIZE.x - 40.0), y))
	g.z_index = 4
	add_child(g)
	gloomlings.append(g)


func float_text(pos: Vector2, text: String, color: Color) -> void:
	var ft := FloatText.new()
	ft.text = text
	ft.color = color
	ft.position = pos
	ft.z_index = 30
	add_child(ft)
	float_texts.append(ft)


func log_event(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > MAX_LOG_LINES:
		log_lines.pop_front()


# --- Rules used by entities ----------------------------------------------------

func choose_shop_for(c: Customer) -> Shop:
	var best: Shop = null
	var best_price := 0
	for s in shops:
		if s.stock(c.wants) <= 0:
			continue
		var p := s.price_of(c.wants)
		if p > c.budget:
			continue
		if s.class_id == "enchanter" and s.ult_active_time > 0.0:
			return s  # Enthrall
		var better := best == null or p < best_price
		if not better and p == best_price:
			better = s.reputation > best.reputation or \
					(s.reputation == best.reputation and randf() < 0.5)
		if better:
			best = s
			best_price = p
	return best


func try_buy(c: Customer, s: Shop) -> bool:
	if s.stock(c.wants) <= 0 or s.price_of(c.wants) > c.budget:
		return false
	var price := s.sell(c.wants)
	float_text(s.position + Vector2(0, -140), "+%dc" % price, Color(1.0, 0.85, 0.3))
	var pname := GameData.potion_name(c.wants)
	if s.is_player:
		log_event("%s bought %s from you for %dc." % [c.kind_name, pname, price])
	else:
		log_event("%s bought %s from %s for %dc." % [c.kind_name, pname, s.display_name, price])
	return true


func find_grove(ing: int, from: Vector2, shop: Shop, exclude: Grove) -> Grove:
	var best: Grove = null
	var best_d := INF
	for g in groves:
		if g == exclude or g.ing != ing or not g.can_harvest(shop):
			continue
		var d := from.distance_to(g.position)
		if d < best_d:
			best_d = d
			best = g
	return best


func count_assigned(g: Grove) -> int:
	var n := 0
	for f in familiars:
		if f.target_grove == g:
			n += 1
	return n


func nearest_prey(pos: Vector2, side: int, radius: float) -> Familiar:
	var best: Familiar = null
	var best_d := radius
	for f in familiars:
		if f.is_down() or f.is_immune() or f.is_safe():
			continue
		var on_side := f.position.y < ROW_TOP if side < 0 else f.position.y > ROW_BOTTOM
		if not on_side:
			continue
		var d := pos.distance_to(f.position)
		if d < best_d:
			best_d = d
			best = f
	return best


func gloom_touch(g: Gloomling, f: Familiar) -> void:
	if g.dead or f.is_down():
		return
	var fname: String = f.shop.data()["familiar"]
	if f.shop.class_id == "hexer" and randf() < GameData.HEXER_BANISH_CHANCE:
		g.dead = true
		float_text(f.position + Vector2(0, -20), "Banished!", Color(1.0, 0.5, 0.5))
		if f.shop.is_player:
			log_event("One of your %s banished a Gloomling!" % fname)
		return
	float_text(f.position + Vector2(0, -20), "Knocked out!", Color(0.8, 0.7, 1.0))
	if f.shop.is_player:
		log_event("A Gloomling knocked out one of your %s. It dropped its load." % fname)
	f.knock_out()


# --- Ultimates -----------------------------------------------------------------

func activate_ult(shop: Shop, target: Variant = null) -> bool:
	if not shop.ult_ready or finished:
		return false
	var d := shop.data()
	match shop.class_id:
		"herbalist":
			for g in groves:
				g.refill()
			shop.ult_active_time = 20.0
		"alchemist":
			shop.ult_active_time = 30.0
		"apothecary":
			for f in shop.familiars:
				f.recover_now()
			shop.ult_active_time = 25.0
		"enchanter":
			shop.ult_active_time = 20.0
		"hexer":
			if not (target is Grove):
				return false
			var grove: Grove = target
			grove.blighted_by = shop
			float_text(grove.position + Vector2(0, -40), "Blighted!", Color(0.8, 0.4, 1.0))
		"seer":
			if not (target is String) or not GameData.BASIC_POTIONS.has(target):
				return false
			favored_potion = target
		_:
			return false
	shop.ult_ready = false
	var who := "You" if shop.is_player else shop.display_name
	var extra := ""
	if shop.class_id == "seer":
		extra = " %s is favored tonight." % GameData.potion_name(favored_potion)
	log_event("%s used %s!%s" % [who, d["ult_name"], extra])
	return true


## Player pressed the ultimate button / Q. Some classes need a target first.
func player_use_ult() -> void:
	if finished or not player_shop.ult_ready:
		return
	match player_class:
		"hexer":
			targeting_blight = true
		"seer":
			hud.open_prophecy_picker()
		_:
			activate_ult(player_shop)


func player_brew_index(i: int) -> void:
	var list := player_shop.recipes()
	if i >= 0 and i < list.size():
		player_shop.start_brew(list[i])


# --- Player input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventMouseButton:
		_handle_mouse(event as InputEventMouseButton)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_handle_key(key)


func _handle_mouse(mb: InputEventMouseButton) -> void:
	var pos := get_global_mouse_position()
	if pos.x > WORLD_SIZE.x:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if targeting_blight:
				var g := grove_at(pos)
				if g != null and activate_ult(player_shop, g):
					targeting_blight = false
				get_viewport().set_input_as_handled()
				return
			_dragging = true
			_drag_start = pos
		elif _dragging:
			_dragging = false
			_finish_selection(pos, mb.shift_pressed)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if targeting_blight:
			targeting_blight = false
		else:
			_command(pos)
		get_viewport().set_input_as_handled()


func _handle_key(key: InputEventKey) -> void:
	match key.keycode:
		KEY_A:
			select_all()
		KEY_R:
			recall_familiars()
		KEY_Q:
			player_use_ult()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			player_brew_index(key.keycode - KEY_1)
		_:
			return
	get_viewport().set_input_as_handled()


func _finish_selection(pos: Vector2, additive: bool) -> void:
	var rect := Rect2(_drag_start, pos - _drag_start).abs()
	if not additive:
		for f in player_shop.familiars:
			f.selected = false
	if rect.size.length() < 6.0:
		var f := familiar_at(pos)
		if f != null:
			f.selected = (not f.selected) if additive else true
	else:
		for f in player_shop.familiars:
			if not f.is_down() and rect.has_point(f.position):
				f.selected = true


func _command(pos: Vector2) -> void:
	var sel := selected_familiars()
	if sel.is_empty():
		return
	var g := grove_at(pos)
	if g != null:
		for f in sel:
			f.assign_grove(g)
		float_text(g.position + Vector2(0, -36), "Gather here!", Color(0.6, 1.0, 0.6))
		return
	if player_shop.counter_rect().has_point(pos):
		for f in sel:
			f.recall()
		return
	var p := _clamp_to_world(pos)
	for i in sel.size():
		var offset := Vector2(float(i % 3 - 1) * 20.0, floorf(i / 3.0) * 20.0)
		sel[i].move_to(p + offset)


func _clamp_to_world(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 10.0, WORLD_SIZE.x - 10.0), clampf(p.y, 10.0, WORLD_SIZE.y - 10.0))


func select_all() -> void:
	for f in player_shop.familiars:
		f.selected = not f.is_down()


func recall_familiars() -> void:
	var sel := selected_familiars()
	if sel.is_empty():
		for f in player_shop.familiars:
			sel.append(f)
	for f in sel:
		f.recall()
	log_event("Familiars recalled to the shop.")


func selected_familiars() -> Array[Familiar]:
	var out: Array[Familiar] = []
	for f in player_shop.familiars:
		if f.selected:
			out.append(f)
	return out


func familiar_at(pos: Vector2) -> Familiar:
	var best: Familiar = null
	var best_d := Familiar.HIT_RADIUS
	for f in player_shop.familiars:
		if f.is_down():
			continue
		var d := pos.distance_to(f.position)
		if d <= best_d:
			best_d = d
			best = f
	return best


func grove_at(pos: Vector2) -> Grove:
	for g in groves:
		if g.contains(pos):
			return g
	return null


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color(0.13, 0.27, 0.17))
	for t in _trees:
		var p: Vector2 = t["pos"]
		var r: float = t["r"]
		var tc: Color = t["color"]
		draw_circle(p + Vector2(0, r * 0.35), r, Color(0, 0, 0, 0.18))
		draw_circle(p, r, tc)

	# Market Row.
	draw_rect(Rect2(0, ROW_TOP, WORLD_SIZE.x, ROW_BOTTOM - ROW_TOP), Color(0.38, 0.33, 0.29))
	for cb in _cobbles:
		var cp: Vector2 = cb["pos"]
		var cc: Color = cb["color"]
		draw_rect(Rect2(cp, Vector2(9, 5)), cc)
	draw_rect(Rect2(0, ROW_TOP - 4, WORLD_SIZE.x, 4), Color(0.25, 0.2, 0.17))
	draw_rect(Rect2(0, ROW_BOTTOM, WORLD_SIZE.x, 4), Color(0.25, 0.2, 0.17))

	# Lanterns, lit at night.
	var font := ThemeDB.fallback_font
	for i in 9:
		var x := 60.0 + i * 135.0
		_draw_lantern(Vector2(x, ROW_TOP + 10.0))
		_draw_lantern(Vector2(x, ROW_BOTTOM - 10.0))
	draw_string(font, Vector2(10, ROW_TOP + 34), "MARKET ROW  (safe from Gloomlings)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.35))


func _draw_lantern(p: Vector2) -> void:
	if is_night:
		draw_circle(p, 26.0, Color(1.0, 0.8, 0.4, 0.12))
		draw_circle(p, 14.0, Color(1.0, 0.8, 0.4, 0.2))
	draw_rect(Rect2(p + Vector2(-2, -2), Vector2(4, 10)), Color(0.15, 0.12, 0.1))
	draw_circle(p, 4.0, Color(1.0, 0.85, 0.5) if is_night else Color(0.45, 0.4, 0.35))


func _draw_overlay() -> void:
	# Faint lines from selected familiars to their groves.
	for f in player_shop.familiars:
		if f.selected and f.target_grove != null and not f.is_down():
			_overlay.draw_line(f.position, f.target_grove.position, Color(0.45, 1.0, 0.55, 0.3), 1.5)
	if _dragging:
		var rect := Rect2(_drag_start, _clamp_to_world(get_global_mouse_position()) - _drag_start).abs()
		_overlay.draw_rect(rect, Color(0.45, 1.0, 0.55, 0.12))
		_overlay.draw_rect(rect, Color(0.45, 1.0, 0.55, 0.8), false, 1.5)
	if targeting_blight:
		var hover := grove_at(get_global_mouse_position())
		for g in groves:
			var w := 3.0 if g == hover else 1.5
			_overlay.draw_arc(g.position, g.radius() + 10.0, 0, TAU, 32, Color(0.8, 0.35, 1.0, 0.8), w)
