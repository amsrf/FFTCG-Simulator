extends "res://scripts/effects/card_effect.gd"
## 1-157C Scholar


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Dull》, put Scholar into the Break Zone: Choose 1 Forward you control. Return it to its owner's hand.",
			"cost": {},
			"tap": true,
			"sacrifice": {"is_source": true},
			"targets": {"is_type": "Forward", "controller": "player"},
			"run": Callable(self, "_return_target"),
		}),
	]

func _return_target(ctx) -> void:
	ctx.return_to_hand(ctx.targets)

