class_name Grove
extends Node2D
## An ingredient node in the Wildwood. Familiars harvest it; it regrows over time.

const RADIUS := 24.0

var ing: int = 0
var rich: bool = false
var amount: float = 0.0
var max_amount: int = 8
var regrow_time: float = 5.0
## While set, only this shop's familiars can harvest here (Hexer's Blight).
var blighted_by: Shop = null

var _t: float = 0.0


func setup(p_ing: int, p_rich: bool, pos: Vector2) -> void:
	ing = p_ing
	rich = p_rich
	position = pos
	max_amount = GameData.RICH_GROVE_MAX if rich else GameData.SMALL_GROVE_MAX
	regrow_time = GameData.RICH_GROVE_REGROW if rich else GameData.SMALL_GROVE_REGROW
	amount = float(max_amount)


func tick(delta: float) -> void:
	_t += delta
	if amount < max_amount:
		amount = minf(float(max_amount), amount + delta / regrow_time)
	queue_redraw()


func available() -> int:
	return int(amount)


func can_harvest(shop: Shop) -> bool:
	if blighted_by != null and blighted_by != shop:
		return false
	return amount >= 1.0


func take(n: int) -> int:
	var got := mini(n, int(amount))
	amount -= float(got)
	return got


func refill() -> void:
	amount = float(max_amount)


func radius() -> float:
	return RADIUS * (1.35 if rich else 1.0)


func contains(p: Vector2) -> bool:
	return position.distance_to(p) <= radius() + 6.0


func _draw() -> void:
	var col: Color = GameData.ING_COLORS[ing]
	var r := radius()
	var blighted := blighted_by != null
	if blighted:
		col = col.lerp(Color(0.35, 0.3, 0.35), 0.65)
	var leaf := col.darkened(0.55)
	if blighted:
		leaf = Color(0.22, 0.17, 0.22)

	draw_circle(Vector2(0, r * 0.4), r * 1.05, Color(0, 0, 0, 0.25))
	draw_circle(Vector2(-r * 0.45, 0), r * 0.62, leaf)
	draw_circle(Vector2(r * 0.45, 0), r * 0.62, leaf)
	draw_circle(Vector2(0, -r * 0.35), r * 0.68, leaf.lightened(0.08))

	# One berry per harvestable unit (capped so it stays readable).
	var fruit := mini(available(), 10)
	for i in fruit:
		var a := TAU * float(i) / 10.0 + 0.4
		var p := Vector2(cos(a), sin(a) * 0.8) * r * 0.55 + Vector2(0, -r * 0.1)
		draw_circle(p, 4.2 if rich else 3.6, col)

	if rich and not blighted:
		var s := 0.5 + 0.5 * sin(_t * 3.0)
		draw_circle(Vector2(r * 0.7, -r * 0.8), 2.0 + s * 1.5, Color(1, 1, 1, 0.5 + s * 0.4))

	# Amount bar + label.
	var w := r * 2.0
	var frac := amount / float(max_amount)
	draw_rect(Rect2(-w / 2.0, r + 4.0, w, 4.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(-w / 2.0, r + 4.0, w * frac, 4.0), col)
	var font := ThemeDB.fallback_font
	var label: String = GameData.ING_NAMES[ing]
	if rich:
		label = "Rich " + label
	draw_string(font, Vector2(-w / 2.0 - 20.0, r + 21.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, w + 40.0, 12, Color(1, 1, 1, 0.85))

	if blighted:
		var hex := Color(0.75, 0.25, 0.95)
		draw_line(Vector2(-r * 0.6, -r * 0.6), Vector2(r * 0.6, r * 0.6), hex, 3.0)
		draw_line(Vector2(r * 0.6, -r * 0.6), Vector2(-r * 0.6, r * 0.6), hex, 3.0)
		draw_string(font, Vector2(-w / 2.0 - 20.0, -r - 8.0), "BLIGHTED",
				HORIZONTAL_ALIGNMENT_CENTER, w + 40.0, 11, hex)
