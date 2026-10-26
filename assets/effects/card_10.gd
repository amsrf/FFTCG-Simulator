extends "res://scripts/effects/card_effect.gd"
## 1-010C Black Mage


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《火》《Dull》, put Black Mage into the Break Zone: Choose 1 Forward. Deal it 4000 damage.",
			"cost": {"火": 1},
			"tap": true,
			"sacrifice": {"is_source": true},
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	ctx.damage(ctx.targets, 4000)
