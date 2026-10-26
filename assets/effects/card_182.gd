extends "res://scripts/effects/card_effect.gd"


func keywords() -> Array[String]:
	return ["brave"]


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Meteorain 《S》《1》《Dull》: Deal 4000 damage to all Forwards opponent controls.",
			"cost": {"neutral": 1},
			"tap": true,
			"s_cost": true,
			"run": Callable(self, "_skill_0"),
		}),
		_ability({
			"text": "Omnislash 《S》《3》《Dull》: Choose 1 Forward. Break it.",
			"cost": {"neutral": 3},
			"tap": true,
			"s_cost": true,
			"targets": {"is_type": "Forward"},
			"target_count": 1,
			"run": Callable(self, "_skill_1"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 4000)

func _skill_1(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	if not targets.is_empty():
		ctx.break_cards(targets)