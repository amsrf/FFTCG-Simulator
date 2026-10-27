extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	if targets.is_empty():
		return
	ctx.apply_damage_division(6000)

func static_rules() -> Dictionary:
	return {"cannot_be_blocked_by": {"min_cost": 4}}

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《S》《Dull》 Choose up to 3 Forwards. Divide 6000 damage among them as you like."
		cost = {}
		tap = true
		s_cost = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))
		target_count = 3
		divide_total = 6000

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
