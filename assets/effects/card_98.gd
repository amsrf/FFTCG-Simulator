extends "res://scripts/effects/card_effect.gd"

func power_modifier(ctx) -> int:
	return ctx.damage_received() * 1000


func properties(ctx) -> Array[String]:
	return ["brave"] if ctx.damage_received() >= 6 else []
