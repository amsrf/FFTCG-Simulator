extends "res://scripts/effects/card_effect.gd"
## 1-112R Delita


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_character": true, "controller": "player"})
	if targets.is_empty():
		return
	ctx.break_cards(targets)


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Northswain's Strike 《S》《Earth》: Choose 1 Forward blocking Delita. Break it.",
			"cost": {"土": 1},
			"s_cost": true,
			"targets": {"is_type": "Forward", "is_blocking": true},
			"target_count": 1,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	if not targets.is_empty():
		ctx.break_cards(targets)