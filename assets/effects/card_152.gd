extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Time Compression 《S》《Water》《Water》《Water》: Freeze all the Forwards other than Ultimecia.",
			"cost": {"水": 3},
			"s_cost": true,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	var targets: Array = ctx.cards_in("field", {"is_type": "Forward", "exclude": {"is_named": "Ultimecia"}})
	ctx.add_status(targets, "frozen", 1)

func static_rules() -> Dictionary:
	return {"on_character_enter": [{
		"targets": {"is_type": "Forward", "exclude": {"is_named": "Ultimecia"}},
		"action": "dull",
	}]}
