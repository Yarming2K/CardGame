class_name Gloomling
extends Node2D
## A night creature that roams one side of the Wildwood and knocks out familiars.
## It can never enter Market Row.

var world: MatchWorld
var side: int = -1  # -1 = north woods, 1 = south woods
var target: Vector2 = Vector2.ZERO
var chasing: Familiar = null
var dead: bool = false

var _t: float = 0.0
var _y_min: float = 0.0
var _y_max: float = 0.0


func setup(p_world: MatchWorld, p_side: int, pos: Vector2) -> void:
	world = p_world
	side = p_side
	if side < 0:
		_y_min = 30.0
		_y_max = MatchWorld.ROW_TOP - 40.0
	else:
		_y_min = MatchWorld.ROW_BOTTOM + 40.0
		_y_max = MatchWorld.WORLD_SIZE.y - 30.0
	position = Vector2(pos.x, clampf(pos.y, _y_min, _y_max))
	target = _random_point()
	_t = randf() * 10.0


func _random_point() -> Vector2:
	return Vector2(randf_range(30.0, MatchWorld.WORLD_SIZE.x - 30.0), randf_range(_y_min, _y_max))


func tick(delta: float) -> void:
	if dead:
		return
	_t += delta
	chasing = world.nearest_prey(position, side, GameData.GLOOM_CHASE_RADIUS)
	var dest := target
	var spd := GameData.GLOOM_SPEED
	if chasing != null:
		dest = chasing.position
		spd = GameData.GLOOM_CHASE_SPEED
	var to := dest - position
	var dist := to.length()
	if chasing == null and dist < 4.0:
		target = _random_point()
	elif dist > 0.001:
		position += to / dist * minf(spd * delta, dist)
	position.y = clampf(position.y, _y_min, _y_max)
	if chasing != null and position.distance_to(chasing.position) < 14.0:
		world.gloom_touch(self, chasing)
	queue_redraw()


func _draw() -> void:
	var wob := sin(_t * 5.0) * 1.5
	var body := Color(0.10, 0.04, 0.16, 0.92)
	draw_circle(Vector2(0, 10), 10.0, Color(0, 0, 0, 0.3))
	draw_circle(Vector2(0, wob), 11.0, body)
	for i in 5:
		var a := TAU * float(i) / 5.0 + _t
		draw_circle(Vector2(cos(a), sin(a)) * 9.0 + Vector2(0, wob), 5.0, body)
	var eye := Color(1.0, 0.25, 0.3) if chasing != null else Color(1.0, 0.9, 0.4)
	draw_circle(Vector2(-4, -2 + wob), 2.2, eye)
	draw_circle(Vector2(4, -2 + wob), 2.2, eye)
