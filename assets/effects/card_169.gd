extends "res://scripts/effects/card_effect.gd"
## 1-169C Scholar


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Dull》: Look at the top card of your deck. You may put it on the bottom.",
			"cost": {},
			"tap": true,
			"run": Callable(self, "_look_top"),
		}),
	]

func _look_top(ctx) -> void:
	await ctx.look_top_may_bottom()

