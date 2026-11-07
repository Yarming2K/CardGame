class_name FloatText
extends Node2D
## A short-lived label that drifts upward and fades (e.g. "+5c").

const LIFE := 1.4

var text: String = ""
var color: Color = Color.WHITE

var _age: float = 0.0


## Advances the animation; returns true when it should be removed.
func tick(delta: float) -> bool:
	_age += delta
	position.y -= 24.0 * delta
	modulate.a = clampf(1.0 - _age / LIFE, 0.0, 1.0)
	return _age >= LIFE


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-80, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, 4,
			Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(-80, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, color)
