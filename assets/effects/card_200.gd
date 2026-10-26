extends "res://scripts/effects/card_effect.gd"
## 1-200C Baralai


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Dull》, put Baralai into the Break Zone: Choose up to 2 Forwards. Activate them.",
			"cost": {},
			"tap": true,
			"sacrifice": {"is_source": true},
			"targets": {"is_type": "Forward"},
			"target_count": 2,
			"run": Callable(self, "_untap_targets"),
		}),
	]

func _untap_targets(ctx) -> void:
	ctx.untap(ctx.targets)

