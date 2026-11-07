class_name RivalAI
extends RefCounted
## Runs an AI shop. It uses the same Shop and Familiar rules as the player:
## assigns familiars to groves, queues brews, prices against the player,
## pulls workers in at night, and fires its ultimate at a sensible moment.
## In multiplayer, this same brain can fill an empty seat.

const THINK_INTERVAL := 0.75
const PRICE_INTERVAL := 3.0
const MAX_QUEUE := 3
const STOCK_CAP := 6

var world: MatchWorld
var shop: Shop

var _think: float = 0.0
var _price_think: float = 0.0
var _phase_time: float = 0.0
var _recall_after: float = 0.0
var _ult_at: float = 0.0
var _recalled: bool = false


func _init(p_world: MatchWorld, p_shop: Shop) -> void:
	world = p_world
	shop = p_shop


func on_phase_change() -> void:
	_phase_time = 0.0
	_recalled = false
	_recall_after = randf_range(1.0, 7.0)
	_ult_at = randf_range(8.0, 30.0) if world.is_night else randf_range(15.0, 50.0)


func tick(delta: float) -> void:
	_phase_time += delta
	_think += delta
	_price_think += delta
	if _think >= THINK_INTERVAL:
		_think = 0.0
		_manage_familiars()
		_manage_brewing()
		_maybe_use_ult()
	if _price_think >= PRICE_INTERVAL:
		_price_think = 0.0
		_manage_prices()


# --- Familiars ---------------------------------------------------------------

func _night_is_dangerous() -> bool:
	if not world.is_night:
		return false
	if shop.class_id == "apothecary" and shop.ult_active_time > 0.0:
		return false
	return shop.class_id != "hexer"  # Imps fight back, so the Hexer keeps working.


func _manage_familiars() -> void:
	if _night_is_dangerous() and _phase_time >= _recall_after:
		if not _recalled:
			_recalled = true
			for f in shop.familiars:
				f.recall()
		return
	_recalled = false
	var need := _ingredient_needs()
	for f in shop.familiars:
		if f.is_down() or f.target_grove != null:
			continue
		if f.state == Familiar.State.RETURNING:
			continue
		var g := _pick_grove(need, f.position)
		if g != null:
			f.assign_grove(g)
			need[g.ing] -= 2.0


func _ingredient_needs() -> Array[float]:
	var need: Array[float] = []
	need.resize(GameData.ING_COUNT)
	need.fill(0.0)
	var plan := _ranked_recipes()
	for i in mini(3, plan.size()):
		var pid: String = plan[i]
		var cost: Dictionary = GameData.POTIONS[pid]["cost"]
		for ing in cost:
			need[ing] += float(cost[ing]) * float(3 - i)
	for i in GameData.ING_COUNT:
		need[i] -= float(shop.ingredients[i])
	for f in shop.familiars:
		if f.cargo > 0 and f.cargo_ing >= 0:
			need[f.cargo_ing] -= float(f.cargo)
		if f.target_grove != null:
			need[f.target_grove.ing] -= 1.5
	return need


func _pick_grove(need: Array[float], from: Vector2) -> Grove:
	var best: Grove = null
	var best_score := -INF
	for g in world.groves:
		if not g.can_harvest(shop) or g.available() < 2:
			continue
		var n: float = maxf(need[g.ing], 0.1)
		var score := n * 10.0 - from.distance_to(g.position) * 0.02 - world.count_assigned(g) * 4.0
		if score > best_score:
			best_score = score
			best = g
	return best


# --- Brewing -----------------------------------------------------------------

func _score(pid: String) -> float:
	var value: float = GameData.POTIONS[pid]["value"]
	var w := 0.9 if GameData.is_signature(pid) else world.demand_weight(pid)
	return w * value / (1.0 + shop.stock(pid) * 0.6)


func _ranked_recipes() -> Array:
	var list: Array = shop.recipes()
	list.sort_custom(func(a, b): return _score(a) > _score(b))
	return list


func _manage_brewing() -> void:
	if shop.brew_queue.size() >= MAX_QUEUE:
		return
	for pid in _ranked_recipes():
		if shop.stock(pid) >= STOCK_CAP:
			continue
		if shop.start_brew(pid):
			return


# --- Pricing -----------------------------------------------------------------

func _manage_prices() -> void:
	var player := world.player_shop
	for pid in shop.recipes():
		var value: int = GameData.POTIONS[pid]["value"]
		var lowest := maxi(1, roundi(value * 0.7))
		var target := value + 2
		if player.knows(pid) and player.stock(pid) > 0:
			target = player.price_of(pid)
			if shop.stock(pid) >= 2 and randf() < 0.7:
				target -= 1  # Undercut.
		if shop.stock(pid) >= 5:
			target -= 1  # Clear out a big stockpile before it spoils.
		shop.set_price(pid, clampi(target, lowest, value * 2))


# --- Ultimate ----------------------------------------------------------------

func _maybe_use_ult() -> void:
	if not shop.ult_ready or _phase_time < _ult_at:
		return
	match shop.class_id:
		"herbalist", "alchemist":
			if not world.is_night:
				world.activate_ult(shop)
		"apothecary", "enchanter":
			if world.is_night and shop.total_potions() >= 3:
				world.activate_ult(shop)
		"hexer":
			if not world.is_night:
				var g := _busiest_player_grove()
				if g != null:
					world.activate_ult(shop, g)
		"seer":
			if not world.is_night:
				world.activate_ult(shop, _best_prophecy())


func _busiest_player_grove() -> Grove:
	var counts: Dictionary = {}
	for f in world.player_shop.familiars:
		if f.target_grove != null:
			counts[f.target_grove] = int(counts.get(f.target_grove, 0)) + 1
	var best: Grove = null
	var best_n := 0
	for g in counts:
		var n: int = counts[g]
		if n > best_n:
			best_n = n
			best = g
	return best


func _best_prophecy() -> String:
	var best: String = GameData.BASIC_POTIONS[0]
	var best_score := -INF
	for pid in GameData.BASIC_POTIONS:
		var s := float(shop.stock(pid)) * 2.0 + world.demand_weight(pid)
		if shop.can_brew(pid):
			s += 1.0
		if s > best_score:
			best_score = s
			best = pid
	return best
