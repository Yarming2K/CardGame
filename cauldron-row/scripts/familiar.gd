class_name Familiar
extends Node2D
## A worker unit. Assign it to a grove and it loops: walk out, gather, carry home.

enum State { IDLE, TO_GROVE, GATHERING, RETURNING, MOVING, KNOCKED_OUT }

const HIT_RADIUS := 14.0

var shop: Shop
var world: MatchWorld
var state: State = State.IDLE
var target_grove: Grove = null
var move_target: Vector2 = Vector2.ZERO
var cargo_ing: int = -1
var cargo: int = 0
var speed: float = 100.0
var carry: int = 2
var selected: bool = false
var ko_left: float = 0.0
var ko_total: float = 1.0

var _gather_acc: float = 0.0
var _bob: float = 0.0
var _home_offset: Vector2 = Vector2.ZERO


func setup(p_shop: Shop, p_world: MatchWorld, index: int) -> void:
	shop = p_shop
	world = p_world
	var d := shop.data()
	speed = d["speed"]
	carry = d["carry"]
	_home_offset = Vector2(-45.0 + index * 24.0, 34.0 + (index % 2) * 10.0)
	position = home_position()
	_bob = randf() * TAU


func home_position() -> Vector2:
	return shop.position + _home_offset


func is_down() -> bool:
	return state == State.KNOCKED_OUT


func is_immune() -> bool:
	return shop.class_id == "apothecary" and shop.ult_active_time > 0.0


func is_safe() -> bool:
	return position.y > MatchWorld.ROW_TOP - 10.0 and position.y < MatchWorld.ROW_BOTTOM + 10.0


func is_working() -> bool:
	return state == State.TO_GROVE or state == State.GATHERING or \
			(state == State.RETURNING and target_grove != null)


# --- Commands ----------------------------------------------------------------

func assign_grove(g: Grove) -> void:
	target_grove = g
	if is_down():
		return  # Resumes this assignment after recovering.
	if cargo > 0 and cargo_ing != g.ing:
		state = State.RETURNING
	else:
		state = State.TO_GROVE


func recall() -> void:
	target_grove = null
	if is_down():
		return
	if cargo > 0:
		state = State.RETURNING
	else:
		move_target = home_position()
		state = State.MOVING


func move_to(p: Vector2) -> void:
	if is_down():
		return
	target_grove = null
	move_target = p
	state = State.MOVING


func knock_out() -> void:
	if is_down():
		return
	cargo = 0
	cargo_ing = -1
	_gather_acc = 0.0
	ko_total = GameData.KO_TIME / (3.0 if shop.class_id == "apothecary" else 1.0)
	ko_left = ko_total
	state = State.KNOCKED_OUT
	position = home_position()  # Limps home to recover.


func recover_now() -> void:
	if is_down():
		ko_left = 0.0
		_recover()


func _recover() -> void:
	state = State.TO_GROVE if target_grove != null else State.IDLE


# --- Simulation --------------------------------------------------------------

func tick(delta: float) -> void:
	_bob += delta * 4.0
	match state:
		State.KNOCKED_OUT:
			ko_left -= delta
			if ko_left <= 0.0:
				_recover()
		State.IDLE:
			pass
		State.MOVING:
			if _step_towards(move_target, delta, 2.0):
				state = State.IDLE
		State.TO_GROVE:
			if target_grove == null:
				state = State.IDLE
			elif _step_towards(target_grove.position, delta, target_grove.radius() * 0.8):
				state = State.GATHERING
				_gather_acc = 0.0
		State.GATHERING:
			_tick_gather(delta)
		State.RETURNING:
			if _step_towards(shop.position + Vector2(0, 14), delta, 6.0):
				_deposit()
	queue_redraw()


func _tick_gather(delta: float) -> void:
	if target_grove == null:
		state = State.IDLE
		return
	if not target_grove.can_harvest(shop):
		var alt := world.find_grove(target_grove.ing, position, shop, target_grove)
		if alt != null:
			target_grove = alt
			state = State.TO_GROVE
		elif cargo > 0:
			state = State.RETURNING
		return  # Otherwise wait here for it to regrow.
	var rate := 1.0
	if shop.class_id == "herbalist" and shop.ult_active_time > 0.0:
		rate = 2.0
	_gather_acc += delta * rate / GameData.GATHER_TIME
	if _gather_acc >= 1.0:
		_gather_acc -= 1.0
		var got := target_grove.take(1)
		if got > 0:
			cargo_ing = target_grove.ing
			cargo += got
		if cargo >= carry:
			state = State.RETURNING


func _deposit() -> void:
	if cargo > 0 and cargo_ing >= 0:
		shop.ingredients[cargo_ing] += cargo
	cargo = 0
	cargo_ing = -1
	if target_grove != null:
		state = State.TO_GROVE
	else:
		move_target = home_position()
		state = State.MOVING


## Moves toward `target`; returns true once within `stop_dist`.
func _step_towards(target: Vector2, delta: float, stop_dist: float) -> bool:
	var to := target - position
	var dist := to.length()
	if dist <= stop_dist:
		return true
	var step := speed * delta
	if step >= dist - stop_dist:
		position += to / dist * (dist - stop_dist)
		return true
	position += to / dist * step
	return false


# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	var c := shop.color
	var bob := sin(_bob) * 1.5
	if is_down():
		var frac := 1.0 - clampf(ko_left / ko_total, 0.0, 1.0)
		draw_circle(Vector2(0, bob), 8.0, Color(0.75, 0.75, 0.85, 0.35))
		draw_arc(Vector2.ZERO, 12.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 24,
				Color(1, 1, 1, 0.7), 2.0)
		return

	draw_circle(Vector2(0, 9), 7.0, Color(0, 0, 0, 0.25))
	if selected:
		draw_arc(Vector2(0, 4), 14.0, 0, TAU, 28, Color(0.45, 1.0, 0.55), 2.0)
	if is_immune():
		draw_arc(Vector2(0, bob), 16.0, 0, TAU, 28, Color(1, 1, 1, 0.6), 2.0)

	var o := Vector2(0, bob)
	match shop.class_id:
		"herbalist":
			draw_circle(o, 7.0, c)
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(0, -6), o + Vector2(-9, -13), o + Vector2(-2, -4)]), c.lightened(0.3))
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(0, -6), o + Vector2(9, -13), o + Vector2(2, -4)]), c.lightened(0.3))
		"alchemist":
			draw_rect(Rect2(o + Vector2(-8, -8), Vector2(16, 16)), c.darkened(0.1))
			draw_rect(Rect2(o + Vector2(-8, -8), Vector2(16, 16)), c.lightened(0.3), false, 2.0)
		"apothecary":
			draw_colored_polygon(PackedVector2Array([
				o, o + Vector2(-11, -7), o + Vector2(-9, 6)]), c.lightened(0.2))
			draw_colored_polygon(PackedVector2Array([
				o, o + Vector2(11, -7), o + Vector2(9, 6)]), c.lightened(0.2))
			draw_circle(o, 4.0, c.darkened(0.3))
		"enchanter":
			draw_circle(o, 10.0, Color(c.r, c.g, c.b, 0.25))
			draw_circle(o, 6.5, Color(c.r, c.g, c.b, 0.6))
			draw_circle(o, 3.5, Color(1, 1, 1, 0.9))
		"hexer":
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(0, -9), o + Vector2(8, 7), o + Vector2(-8, 7)]), c)
			draw_line(o + Vector2(-4, -5), o + Vector2(-7, -12), c.darkened(0.3), 2.0)
			draw_line(o + Vector2(4, -5), o + Vector2(7, -12), c.darkened(0.3), 2.0)
		"seer":
			draw_circle(o, 7.0, Color(0.15, 0.13, 0.22))
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(6, -2), o + Vector2(13, 0), o + Vector2(6, 2)]), Color(1.0, 0.8, 0.3))
			draw_arc(o, 7.0, PI, TAU, 12, c, 2.0)
		_:
			draw_circle(o, 7.0, c)

	# Eyes.
	draw_circle(o + Vector2(-2.5, -1), 1.4, Color.WHITE)
	draw_circle(o + Vector2(2.5, -1), 1.4, Color.WHITE)

	if cargo > 0 and cargo_ing >= 0:
		draw_circle(o + Vector2(9, -11), 4.0, GameData.ING_COLORS[cargo_ing])
		if cargo > 1:
			draw_string(ThemeDB.fallback_font, o + Vector2(13, -7), str(cargo),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
