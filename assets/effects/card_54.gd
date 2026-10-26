extends "res://scripts/effects/card_effect.gd"
## 1-054C Dark Knight


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《氷》《氷》《Dull》: Deal 1000 damage to all opponent Forwards.",
			"cost": {"氷": 2},
			"tap": true,
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 1000)
