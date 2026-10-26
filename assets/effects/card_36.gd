extends "res://scripts/effects/card_effect.gd"
## 1-036C Bard


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《氷》《Dull》, put Bard into the Break Zone: Your opponent discards 1 card.",
			"cost": {"氷": 1},
			"tap": true,
			"sacrifice": {"is_source": true},
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	await ctx.opponent_discards(1)
