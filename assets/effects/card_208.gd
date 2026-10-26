extends "res://scripts/effects/card_effect.gd"


func keywords() -> Array[String]:
	return ["haste"]

func conditional_powers() -> Array:
	return [{"value": 2000, "condition": Callable(self, "_has_serah")}]


func _has_serah(source: Card) -> bool:
	return controls(source, {"is_named": "Serah"})
