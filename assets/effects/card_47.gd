extends "res://scripts/effects/card_effect.gd"
## 1-047R Terra
## 《Ice》: Choose 1 dull Forward. Deal it 1000 damage.


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《氷》: Choose 1 dull Forward. Deal it 1000 damage.",
			"cost": {"氷": 1},
			"tap": false,
			"targets": {"is_type": "Forward", "is_tapped": true},
			"run": Callable(self, "_ice_shot"),
		}),
	]


func _ice_shot(ctx) -> void:
	ctx.damage(ctx.targets, 1000)

func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({
		"is_type": "Forward", "controller": "opponent", "is_tapped": true,
	}, 2)
	ctx.damage(targets, 4000)
