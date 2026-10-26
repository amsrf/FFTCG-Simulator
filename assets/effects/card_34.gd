extends "res://scripts/effects/card_effect.gd"
## 1-034C Shiva


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《氷》《氷》《氷》《Dull》: Dull all opponent Forwards.",
			"cost": {"氷": 3},
			"tap": true,
			"run": Callable(self, "_dull_all_opponent_forwards"),
		}),
	]

func _dull_all_opponent_forwards(ctx) -> void:
	ctx.dull(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}))

