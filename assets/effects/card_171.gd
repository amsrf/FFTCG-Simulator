extends "res://scripts/effects/card_effect.gd"

func static_rules() -> Dictionary:
	return {"damage_modifiers": [{"targets": {"is_type": "Forward", "controller": "player"}, "conditions": [{"compare_values": {"left": {"context": "amount"}, "op": "lt", "right": {"context": "target", "property": "power"}}}], "operation": "set", "value": 0}]}
