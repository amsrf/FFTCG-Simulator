extends "res://scripts/effects/card_effect.gd"
## 1-048C Devout


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Dull, put Devout into the Break Zone: Play 1 Forward of cost 4 or less from your Break Zone.",
			"cost": {},
			"tap": true,
			"sacrifice": {"is_source": true},
			"only_your_turn": true,
			"run": Callable(self, "_play_from_break_zone"),
		}),
	]

func _play_from_break_zone(ctx) -> void:
	await ctx.play_from_break_zone({"is_type": "Forward", "is_cost_lower_than": 5})

