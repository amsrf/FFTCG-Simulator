extends "res://scripts/effects/card_effect.gd"

func static_rules() -> Dictionary:
	return {"shields": {"targets": {"is_named": "Sazh"}, "from": "opponent", "by": ["Summon", "Ability"]}}
