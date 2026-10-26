extends "res://scripts/effects/card_effect.gd"
## 1-089C Thief


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《風》《Dull》: Your opponent mills 1.",
			"cost": {"風": 1},
			"tap": true,
			"run": Callable(self, "_mill_one"),
		}),
		_ability({
			"text": "《S》《風》《Dull》: Your opponent mills 2. You draw 1.",
			"s_cost": true,
			"cost": {"風": 1},
			"tap": true,
			"run": Callable(self, "_mill_two_draw"),
		}),
	]

func _mill_one(ctx) -> void:
	await ctx.opponent_mills(1)

func _mill_two_draw(ctx) -> void:
	await ctx.opponent_mills(2)
	ctx.draw(ctx.owner_id, 1)

