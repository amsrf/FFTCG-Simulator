extends "res://scripts/effects/card_effect.gd"


func keywords() -> Array[String]:
	return ["brave"]


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Strongest Sword 《S》《Dull》: Choose 1 Forward. Remove the top card of your deck from the game. If it is a Forward, break it; if not, deal 3000 damage.",
			"cost": {},
			"tap": true,
			"s_cost": true,
			"targets": {"is_type": "Forward"},
			"target_count": 1,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.reveal_top(1)
	if ctx.check_revealed(0, {"is_type": "Forward"}):
		ctx.break_cards(targets)
	else:
		ctx.damage(targets, 3000)
	ctx.remove_revealed_from_game(0)