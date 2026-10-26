extends "res://scripts/effects/card_effect.gd"
## 1-104R Kefka


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Dull》: Choose 1 Forward you control. It gains +5000 power. At the end of the turn, break it.",
			"cost": {},
			"tap": true,
			"targets": {"is_type": "Forward", "controller": "your"},
			"run": Callable(self, "_kefka_pump"),
		}),
	]

func _kefka_pump(ctx) -> void:
	ctx.power_change(ctx.targets, 5000, 1)
	ctx.add_status(ctx.targets, "break_at_end_of_turn", 1)

