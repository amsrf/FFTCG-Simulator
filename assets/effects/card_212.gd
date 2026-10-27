extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-212S Shuyin


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT).cost_at_most(3)))
	await ctx.return_to_hand(targets)


func ex_burst_event() -> String:
	return "when_enter_field"
