extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Highwind 《S》《Dull》: Your opponent puts the top 2 cards of their deck into the Break Zone.",
			"cost": {},
			"tap": true,
			"s_cost": true,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	await ctx.opponent_mills(2)

func damage_caused_riders() -> Array:
	return [{
		"status": "cid_verdict",
		"duration": 1,
		"on_enter_break_zone": [{"name": "opponent_mills", "author": "game", "argument": [2]}],
	}]
