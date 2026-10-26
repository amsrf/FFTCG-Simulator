extends "res://scripts/effects/card_effect.gd"

func static_rules() -> Dictionary:
	return {"cannot_be_blocked_by": {"min_cost": 3}}
