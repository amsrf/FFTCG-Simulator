extends "res://scripts/effects/card_effect.gd"

func static_rules() -> Dictionary:
	return {"damage_modifiers": [{"targets": {"is_type": "Forward", "exclude": {"is_source": true}}, "conditions": [{"in_party_with_self": true}], "operation": "set", "value": 0}]}
