extends "res://scripts/effects/card_effect.gd"
## 1-053C Summoner


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Ice》, put Summoner into the Break Zone: Choose 1 Summon. Cancel its effect.",
			"cost": {"氷": 1},
			"sacrifice": {"is_source": true},
			"targets": {"in": "stack", "is_type": "Summon"},
			"run": Callable(self, "_cancel_summon"),
		}),
	]

func _cancel_summon(ctx) -> void:
	if not ctx.targets.is_empty():
		ctx.cancel_stack_card(ctx.targets[0])

