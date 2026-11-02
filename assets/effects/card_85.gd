extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = ctx.targets.duplicate()
	if targets.is_empty():
		return
	ctx.apply_damage_division(6000)

func allows_blocker(_owner: Card, blocker: Card) -> bool:
	return int(blocker.cost) < 4

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

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)
