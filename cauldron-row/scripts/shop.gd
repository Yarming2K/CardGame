class_name Shop
extends Node2D
## A potion shop on Market Row: stockpile, cauldron, prices, and familiars.
## The same class is used for the player's shop and AI rivals.

var world: MatchWorld
var class_id: String = ""
var is_player: bool = false
var display_name: String = ""
var color: Color = Color.WHITE

var ingredients: Array[int] = []
var potions: Dictionary = {}  # potion id -> count in stock
var prices: Dictionary = {}  # potion id -> asking price
var coins: int = 0
var reputation: int = GameData.START_REPUTATION
var potions_sold: int = 0

var brew_queue: Array[String] = []
var brew_progress: float = 0.0

var familiars: Array[Familiar] = []

var ult_ready: bool = true
## Seconds left on a timed ultimate (Overgrowth, Philosopher's Hour, Panacea, Enthrall).
var ult_active_time: float = 0.0

var _greenhouse_acc: float = 0.0
var _t: float = 0.0


func setup(p_world: MatchWorld, p_class: String, p_player: bool, pos: Vector2) -> void:
	world = p_world
	class_id = p_class
	is_player = p_player
	position = pos
	var d := data()
	color = d["color"]
	if is_player:
		display_name = "Your %s shop" % d["name"]
	else:
		display_name = d["shop_name"]
	ingredients.resize(GameData.ING_COUNT)
	ingredients.fill(GameData.START_INGREDIENTS)
	for pid in recipes():
		potions[pid] = 0
		prices[pid] = int(GameData.POTIONS[pid]["value"])


func data() -> Dictionary:
	return GameData.CLASSES[class_id]


func recipes() -> Array:
	return GameData.recipes_for(class_id)


func knows(pid: String) -> bool:
	return potions.has(pid)


func stock(pid: String) -> int:
	return int(potions.get(pid, 0))


func price_of(pid: String) -> int:
	return int(prices.get(pid, 999))


func set_price(pid: String, value: int) -> void:
	if prices.has(pid):
		prices[pid] = clampi(value, GameData.MIN_PRICE, GameData.MAX_PRICE)


func total_potions() -> int:
	var n := 0
	for pid in potions:
		n += int(potions[pid])
	return n


func total_ingredients() -> int:
	var n := 0
	for c in ingredients:
		n += c
	return n


func wildcard_active() -> bool:
	return class_id == "alchemist" and ult_active_time > 0.0


func brew_time(pid: String) -> float:
	var t: float = GameData.POTIONS[pid]["time"]
	if class_id == "alchemist":
		t *= 0.75
	return t


func can_brew(pid: String) -> bool:
	if not knows(pid) or brew_queue.size() >= GameData.MAX_QUEUE:
		return false
	var cost: Dictionary = GameData.POTIONS[pid]["cost"]
	if wildcard_active():
		var need := 0
		for ing in cost:
			need += int(cost[ing])
		return total_ingredients() >= need
	for ing in cost:
		if ingredients[ing] < int(cost[ing]):
			return false
	return true


func start_brew(pid: String) -> bool:
	if not can_brew(pid):
		return false
	var cost: Dictionary = GameData.POTIONS[pid]["cost"]
	var deficit := 0
	for ing in cost:
		var n: int = cost[ing]
		var take_n := mini(n, ingredients[ing])
		ingredients[ing] -= take_n
		deficit += n - take_n
	# Only non-zero during Philosopher's Hour: pay with whatever we have most of.
	while deficit > 0:
		var best := most_stocked(-1)
		if best < 0 or ingredients[best] <= 0:
			break
		ingredients[best] -= 1
		deficit -= 1
	brew_queue.append(pid)
	return true


## Index of the ingredient we hold most of, ignoring `exclude`. -1 if none.
func most_stocked(exclude: int) -> int:
	var best := -1
	for i in GameData.ING_COUNT:
		if i == exclude:
			continue
		if best < 0 or ingredients[i] > ingredients[best]:
			best = i
	return best


func can_transmute(target: int) -> bool:
	if class_id != "alchemist":
		return false
	var src := most_stocked(target)
	return src >= 0 and ingredients[src] >= 2


## Alchemist: 2 of the most-stocked ingredient become 1 of `target`.
func transmute(target: int) -> bool:
	if not can_transmute(target):
		return false
	var src := most_stocked(target)
	ingredients[src] -= 2
	ingredients[target] += 1
	return true


func sell(pid: String) -> int:
	var price := price_of(pid)
	potions[pid] = stock(pid) - 1
	coins += price
	reputation += 2 if class_id == "apothecary" else 1
	potions_sold += 1
	return price


## Called at dawn. Returns how many potions were lost.
func spoil_potions() -> int:
	if class_id == "enchanter":
		return 0
	var lost := 0
	for pid in potions.keys():
		var n: int = potions[pid]
		var gone := int(floor(n * GameData.SPOIL_FRACTION))
		potions[pid] = n - gone
		lost += gone
	return lost


func counter_rect() -> Rect2:
	return Rect2(position + Vector2(-75, -115), Vector2(150, 125))


func tick(delta: float) -> void:
	_t += delta
	if ult_active_time > 0.0:
		ult_active_time = maxf(0.0, ult_active_time - delta)

	if brew_queue.is_empty():
		brew_progress = 0.0
	else:
		brew_progress += delta
		var pid: String = brew_queue[0]
		if brew_progress >= brew_time(pid):
			brew_progress = 0.0
			brew_queue.pop_front()
			potions[pid] = stock(pid) + 1
			if is_player:
				world.float_text(position + Vector2(62, -40), "+1 " + GameData.potion_name(pid),
						GameData.potion_color(pid))

	if class_id == "herbalist":
		_greenhouse_acc += delta
		if _greenhouse_acc >= GameData.GREENHOUSE_INTERVAL:
			_greenhouse_acc -= GameData.GREENHOUSE_INTERVAL
			var ing := randi() % GameData.ING_COUNT
			ingredients[ing] += 1
			if is_player:
				world.float_text(position + Vector2(-60, -40), "+1 " + GameData.ING_NAMES[ing],
						GameData.ING_COLORS[ing])

	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font

	if ult_active_time > 0.0:
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		draw_arc(Vector2(0, -45), 90.0 + pulse * 6.0, 0, TAU, 48,
				Color(color.r, color.g, color.b, 0.35 + pulse * 0.3), 4.0)

	# Building.
	draw_rect(Rect2(-72, -6, 144, 12), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(-62, -78, 124, 78), Color(0.40, 0.29, 0.22))
	draw_rect(Rect2(-50, -38, 100, 38), Color(0.22, 0.15, 0.11))
	var roof := PackedVector2Array([
		Vector2(-76, -76), Vector2(76, -76), Vector2(54, -112), Vector2(-54, -112),
	])
	draw_colored_polygon(roof, color.darkened(0.25))
	var stripe_w := 124.0 / 6.0
	for i in 6:
		var stripe := color.lightened(0.2) if i % 2 == 0 else color.darkened(0.05)
		draw_rect(Rect2(-62 + i * stripe_w, -78, stripe_w, 14), stripe)
	draw_rect(Rect2(-56, -42, 112, 7), Color(0.55, 0.40, 0.28))

	# Bottles on the counter: one per known potion, with stock count.
	var pids := recipes()
	var step := 104.0 / float(pids.size())
	for i in pids.size():
		var pid: String = pids[i]
		var x := -52.0 + step * (i + 0.5)
		var n := stock(pid)
		var pc := GameData.potion_color(pid)
		if n <= 0:
			pc = Color(pc.r, pc.g, pc.b, 0.25)
		draw_rect(Rect2(x - 2, -60, 4, 5), Color(0.8, 0.75, 0.7, pc.a))
		draw_circle(Vector2(x, -50), 6.0, pc)
		draw_string(font, Vector2(x - 10, -26), str(n), HORIZONTAL_ALIGNMENT_CENTER, 20, 11,
				Color(1, 1, 1, 0.9 if n > 0 else 0.4))

	# Cauldron.
	var cpos := Vector2(78, -12)
	draw_circle(cpos + Vector2(0, 8), 16.0, Color(0, 0, 0, 0.3))
	draw_circle(cpos, 15.0, Color(0.12, 0.12, 0.14))
	draw_rect(Rect2(cpos.x - 17, cpos.y - 13, 34, 5), Color(0.25, 0.25, 0.28))
	if not brew_queue.is_empty():
		var pid: String = brew_queue[0]
		var bc := GameData.potion_color(pid)
		draw_circle(cpos + Vector2(0, -9), 11.0, bc.darkened(0.2))
		for b in 3:
			var phase := fmod(_t * 1.3 + b * 0.33, 1.0)
			draw_circle(cpos + Vector2(-6 + b * 6, -12 - phase * 18), 2.5 * (1.0 - phase) + 1.0,
					Color(bc.r, bc.g, bc.b, 1.0 - phase))
		var frac := clampf(brew_progress / brew_time(pid), 0.0, 1.0)
		draw_arc(cpos, 20.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 32, bc, 3.0)

	# Name plate.
	var title := display_name
	if is_player:
		title = "YOU - " + title
	draw_string_outline(font, Vector2(-110, -120), title, HORIZONTAL_ALIGNMENT_CENTER, 220, 14, 4,
			Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(-110, -120), title, HORIZONTAL_ALIGNMENT_CENTER, 220, 14,
			color.lightened(0.35))
