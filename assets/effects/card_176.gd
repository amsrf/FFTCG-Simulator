extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-176H Yuna


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")))
	await ctx.return_to_hand(targets)


func ex_burst_event() -> String:
	return "when_enter_field"

func static_rules() -> Dictionary:
	return {"break_zone_exile": true}
