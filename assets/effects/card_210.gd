extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## Lightning 1-210R: costs 1 less for each other Category XIII Forward you control.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.CAUSE_DAMAGE_TO_PLAYER, "when_cause_damage_to_player"),
	]


func modify_cost(ctx: COST_CONTEXT, _card: Card, cost: Dictionary) -> Dictionary:
	var count: int = ctx.cards_in_field(
		CARD_QUERY.new().of_category("XIII").of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR), true).size()
	return ctx.adjust(cost, -count)


func keywords() -> Array[String]:
	return ["haste"]

func when_cause_damage_to_player(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)))
	ctx.dull(targets)
