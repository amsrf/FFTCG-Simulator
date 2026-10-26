extends "res://scripts/effects/card_effect.gd"

func conditional_powers() -> Array:
	return [
		{"value": 2000, "condition": Callable(self, "_has_yuna")},
		{"value": 2000, "condition": Callable(self, "_has_paine")},
	]


func _has_yuna(source: Card) -> bool:
	return controls(source, {"is_named": "Yuna"})


func _has_paine(source: Card) -> bool:
	return controls(source, {"is_named": "Paine"})

func static_rules() -> Dictionary:
	return {"conditional_cannot_be_chosen": [{"if_controls": {"is_named": "Yuna"}, "sources": ["Summon"]}, {"if_controls": {"is_named": "Paine"}, "sources": ["Ability"]}]}
