extends "res://scripts/effects/card_effect.gd"
## 1-096C Mystic


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Put 1 Backup into the Break Zone: Mystic gains +3000 power until the end of the turn.",
			"cost": {},
			"sacrifice": {"is_type": "Backup", "controller": "player"},
			"run": Callable(self, "_self_pump"),
		}),
	]

func _self_pump(ctx) -> void:
	ctx.source.power_change(3000, 1)

