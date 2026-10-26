extends "res://scripts/effects/card_effect.gd"
## 1-128R Gilgamesh


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Gilgamesh Morphing Time 《S》《雷》《雷》: Double its power, gain First Strike and Brave, and attack twice.",
			"s_cost": true,
			"cost": {"雷": 2},
			"only_your_turn": true,
			"run": Callable(self, "_morphing_time"),
		}),
	]

func _morphing_time(ctx) -> void:
	ctx.source.double_power(1)
	ctx.add_status([ctx.source], "first_strike", 1)
	ctx.add_status([ctx.source], "brave", 1)
	ctx.source.set_extra_attacks(1)

