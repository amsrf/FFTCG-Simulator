extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## Lightning 1-210R: costs 1 less for each other Category XIII Forward you control.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAUSE_DAMAGE_TO_PLAYER: Callable(self, "when_cause_damage_to_player"),
	}


func modify_cost(ctx: COST_CONTEXT, _card: Card, cost: Dictionary) -> Dictionary:
	var count: int = ctx.cards_in_field(
		{"is_category": "XIII", "is_type": "Forward", "controller": "your"}, true).size()
	return ctx.adjust(cost, -count)


func keywords() -> Array[String]:
	return ["haste"]

func when_cause_damage_to_player(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)))
	ctx.dull(targets)
