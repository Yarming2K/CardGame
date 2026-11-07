class_name Customer
extends Node2D
## A shopper walking down Market Row. Wants one potion and has a budget;
## buys from the cheapest shop that stocks it (ties go to higher reputation).

enum Mood { LOOKING, HAPPY, SAD }

const KINDS = [
	{"name": "A Moth Spirit", "color": Color(0.92, 0.86, 0.62)},
	{"name": "A Lost Child", "color": Color(0.95, 0.72, 0.62)},
	{"name": "A Frost Hag", "color": Color(0.72, 0.86, 0.96)},
	{"name": "A Grumbling Ghost", "color": Color(0.86, 0.86, 0.96)},
	{"name": "A Swamp Toad", "color": Color(0.46, 0.72, 0.36)},
	{"name": "A Lantern Fox", "color": Color(0.96, 0.56, 0.26)},
	{"name": "A Clockwork Owl", "color": Color(0.72, 0.62, 0.42)},
]
const PATIENCE := 22.0

var world: MatchWorld
var kind_name: String = ""
var body_color: Color = Color.WHITE
var wants: String = ""
var budget: int = 0
var connoisseur: bool = false
var dir: float = 1.0
var speed: float = 70.0
var target_shop: Shop = null
var mood: Mood = Mood.LOOKING
var done: bool = false

var _recheck: float = 0.0
var _patience: float = PATIENCE
var _t: float = 0.0


func setup(p_world: MatchWorld, p_wants: String, p_budget: int, from_left: bool,
		p_connoisseur: bool) -> void:
	world = p_world
	wants = p_wants
	budget = p_budget
	connoisseur = p_connoisseur
	var kind: Dictionary = KINDS.pick_random()
	kind_name = kind["name"]
	body_color = kind["color"]
	if connoisseur:
		kind_name = "A connoisseur"
	dir = 1.0 if from_left else -1.0
	speed = randf_range(60.0, 80.0)
	var start_x := -20.0 if from_left else MatchWorld.WORLD_SIZE.x + 20.0
	position = Vector2(start_x, MatchWorld.LANE_Y + randf_range(-6.0, 6.0))
	_t = randf() * 10.0


func tick(delta: float) -> void:
	_t += delta
	if mood == Mood.LOOKING:
		_patience -= delta
		if _patience <= 0.0:
			mood = Mood.SAD
		else:
			if target_shop == null:
				_recheck -= delta
				if _recheck <= 0.0:
					_recheck = 1.0
					target_shop = world.choose_shop_for(self)
			if target_shop != null:
				var tx := target_shop.position.x
				if absf(tx - position.x) <= speed * delta + 1.0:
					position.x = tx
					if world.try_buy(self, target_shop):
						mood = Mood.HAPPY
					target_shop = null
					_recheck = 0.0
				else:
					position.x += signf(tx - position.x) * speed * delta
				queue_redraw()
				return
	position.x += dir * speed * delta
	if position.x < -40.0 or position.x > MatchWorld.WORLD_SIZE.x + 40.0:
		done = true
	queue_redraw()


func _draw() -> void:
	var step := sin(_t * 8.0) * 1.5
	draw_circle(Vector2(0, 11), 8.0, Color(0, 0, 0, 0.25))
	draw_circle(Vector2(0, 2 + step * 0.3), 9.0, body_color.darkened(0.15))
	draw_circle(Vector2(0, -10), 6.5, body_color)
	draw_circle(Vector2(-2.2, -11), 1.2, Color(0.1, 0.1, 0.1))
	draw_circle(Vector2(2.2, -11), 1.2, Color(0.1, 0.1, 0.1))

	# Thought bubble.
	var b := Vector2(0, -32)
	match mood:
		Mood.LOOKING:
			var pc := GameData.potion_color(wants)
			var rim := Color(1.0, 0.85, 0.3) if connoisseur else Color(1, 1, 1, 0.9)
			draw_circle(b, 10.0, Color(1, 1, 1, 0.92))
			draw_arc(b, 10.0, 0, TAU, 24, rim, 2.0 if connoisseur else 1.0)
			draw_rect(Rect2(b + Vector2(-1.5, -7), Vector2(3, 4)), Color(0.5, 0.45, 0.4))
			draw_circle(b + Vector2(0, 1), 5.0, pc)
		Mood.HAPPY:
			draw_circle(b + Vector2(-3, -1), 4.0, Color(1.0, 0.4, 0.55))
			draw_circle(b + Vector2(3, -1), 4.0, Color(1.0, 0.4, 0.55))
			draw_colored_polygon(PackedVector2Array([
				b + Vector2(-7, 0), b + Vector2(7, 0), b + Vector2(0, 8)]), Color(1.0, 0.4, 0.55))
		Mood.SAD:
			draw_circle(b, 9.0, Color(0.6, 0.6, 0.65, 0.85))
			for i in 3:
				draw_circle(b + Vector2(-4 + i * 4, 0), 1.3, Color(0.2, 0.2, 0.25))
