extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《雷》《雷》: Gilgamesh gains +1000 power until the end of the turn.",
			"cost": {"雷": 2},
			"run": Callable(self, "_skill_0"),
		}),
		_ability({
			"text": "Divider 《S》《雷》《雷》: Choose 1 Forward. Break it. Use only if you have received 4+ damage.",
			"cost": {"雷": 2},
			"s_cost": true,
			"only_if_damage_received": 4,
			"targets": {"is_type": "Forward"},
			"target_count": 1,
			"run": Callable(self, "_skill_1"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.power_change([ctx.source], 1000, 1)

func _skill_1(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	if not targets.is_empty():
		ctx.break_cards(targets)

func static_rules() -> Dictionary:
	return {"cannot_be_returned_to_hand": {"sources": ["Summon", "Ability"], "controller": "opponent"}}
