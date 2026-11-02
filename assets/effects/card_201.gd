extends "res://scripts/effects/card_effect.gd"

func conditional_powers() -> Array:
	return [
		{"value": 2000, "condition": Callable(self, "_has_yuna")},
		{"value": 2000, "condition": Callable(self, "_has_paine")},
	]


func _has_yuna(source: Card) -> bool:
	return controls(source, CARD_QUERY.new().named("Yuna"))


func _has_paine(source: Card) -> bool:
	return controls(source, CARD_QUERY.new().named("Paine"))

func prevents_being_chosen(ctx: TARGET_CONTEXT) -> bool:
	if not ctx.from_opponent():
		return false
	if ctx.is_kind("Summon") and ctx.controls(CARD_QUERY.new().named("Yuna")):
		return true
	if ctx.is_kind("Ability") and ctx.controls(CARD_QUERY.new().named("Paine")):
		return true
	return false
