extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = ctx.targets.duplicate()
	if not targets.is_empty():
		ctx.break_cards(targets)

func power_modifier(ctx: EFFECT_CONTEXT) -> int:
	return ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)).size() * 1000

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Ultimate Jecht Shot 《S》《Fire》《2》《Dull》: Choose 1 Forward. Break it."
		cost = {"火": 1, "neutral": 2}
		tap = true
		s_cost = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))
		target_count = 1

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)
