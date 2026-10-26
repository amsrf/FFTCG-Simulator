extends "res://scripts/effects/card_effect.gd"
## 1-160C Gordon


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Dull》: The next damage dealt to Gordon becomes 0 this turn.",
			"cost": {},
			"tap": true,
			"run": Callable(self, "_next_damage_zero"),
		}),
	]

func _next_damage_zero(ctx) -> void:
	ctx.add_status([ctx.source], "next_receiving_damage", 1, {"operation": "set", "value": 0})

