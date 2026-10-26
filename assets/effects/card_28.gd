extends "res://scripts/effects/card_effect.gd"
## 1-028 enter-the-field ability


func when_enter_field(ctx) -> void:
	await ctx.search_deck({"is_named": "Lann"})


func ex_burst_event() -> String:
	return "when_enter_field"


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《Fire》《1》《Dull》: Choose 1 Lann. It gains +1000 power until the end of the turn.",
			"cost": {"火": 1, "neutral": 1},
			"tap": true,
			"targets": {"is_named": "Lann"},
			"target_count": 1,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.power_change(targets, 1000, 1)