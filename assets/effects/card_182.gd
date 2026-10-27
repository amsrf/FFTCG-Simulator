extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")


func keywords() -> Array[String]:
	return ["brave"]


func activated_abilities() -> Array:
	return [Ability0.new(self), Ability1.new(self)]
func _skill_0(ctx) -> void:
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 4000)

func _skill_1(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	if not targets.is_empty():
		ctx.break_cards(targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Meteorain 《S》《1》《Dull》: Deal 4000 damage to all Forwards opponent controls."
		cost = {"neutral": 1}
		tap = true
		s_cost = true

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)

class Ability1 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Omnislash 《S》《3》《Dull》: Choose 1 Forward. Break it."
		cost = {"neutral": 3}
		tap = true
		s_cost = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))
		target_count = 1

	func on_resolve(ctx) -> void:
		await _owner._skill_1(ctx)
