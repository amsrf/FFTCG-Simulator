extends "res://scripts/effects/card_effect.gd"

func static_rules() -> Dictionary:
	return {"cannot_be_blocked_by": {"greater_power": true}, "cannot_block": {"greater_power": true}}
