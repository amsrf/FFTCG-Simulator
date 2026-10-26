extends "res://scripts/effects/card_effect.gd"
## 1-146C Ricard


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Lightning》, put Ricard into the Break Zone: Choose 1 Forward. It cannot be broken this turn.",
			"cost": {"雷": 1},
			"sacrifice": {"is_source": true},
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_unbreakable_target"),
		}),
	]

func _unbreakable_target(ctx) -> void:
	ctx.add_status(ctx.targets, "unbreakable", 1)

