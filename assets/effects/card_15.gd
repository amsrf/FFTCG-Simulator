extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	if not targets.is_empty():
		ctx.break_cards(targets)

func power_per_rules() -> Array:
	return [{"count": {"is_type": "Forward", "controller": "opponent"}, "value": 1000}]

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Ultimate Jecht Shot 《S》《Fire》《2》《Dull》: Choose 1 Forward. Break it."
		cost = {"火": 1, "neutral": 2}
		tap = true
		s_cost = true
		targets = {"is_type": "Forward"}
		target_count = 1

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
