extends "res://scripts/effects/card_effect.gd"
## 1-066C Dancer


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Dull》: Deal 1000 damage to all opponent Forwards.",
			"cost": {},
			"tap": true,
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 1000)
