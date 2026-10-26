extends "res://scripts/effects/card_effect.gd"

func static_rules() -> Dictionary:
	return {"must_be_chosen": {"sources": ["Summon", "Ability"], "controller": "opponent"}}
