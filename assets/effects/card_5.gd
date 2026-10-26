extends "res://scripts/effects/card_effect.gd"

func static_rules() -> Dictionary:
	return {"damage_modifiers": [{"targets": {"is_type": "Forward", "is_cost_at_least": 4}, "conditions": [{"source_is_self": true}], "operation": "multiply", "value": 2}]}
