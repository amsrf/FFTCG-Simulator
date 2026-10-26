extends "res://scripts/effects/card_effect.gd"

func static_rules() -> Dictionary:
	return {"protects": {"targets": {"is_type": "Backup", "controller": "player"}, "from": "opponent", "by": ["Summon", "Ability"]}}
