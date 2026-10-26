extends "res://scripts/effects/card_effect.gd"

func static_rules() -> Dictionary:
	return {"cannot_be_chosen": {"sources": ["Summon", "Ability"], "controller": "opponent"}}
