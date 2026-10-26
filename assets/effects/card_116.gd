extends "res://scripts/effects/card_effect.gd"
## 1-116 Prishe: when this card blocks, it gains +4000.


func when_blocks(ctx) -> void:
	ctx.power_change([ctx.source], 4000, 1)


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Earth》: Prishe gains Brave until the end of the turn.",
			"cost": {"土": 1},
			"run": Callable(self, "_skill_0"),
		}),
		_ability({
			"text": "Auroral Uppercut 《S》《Earth》: Double the power of Prishe until the end of the turn.",
			"cost": {"土": 1},
			"s_cost": true,
			"run": Callable(self, "_skill_1"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.add_status([ctx.source], "brave", 1)

func _skill_1(ctx) -> void:
	ctx.power_change([ctx.source], ctx.source.power, 1)