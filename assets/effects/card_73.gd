extends "res://scripts/effects/card_effect.gd"

func damage_caused_riders() -> Array:
	return [{
		"status": "cid_verdict",
		"duration": 1,
		"on_enter_break_zone": [{"name": "opponent_mills", "author": "game", "argument": [2]}],
	}]
