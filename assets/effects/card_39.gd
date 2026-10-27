extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-039C Shiva


func cast_target_criteria(_ctx) -> Variant:
	return TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").tapped(true))


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").tapped(true)))
	ctx.damage(targets, 5000)


func ex_burst_event() -> String:
	return "when_cast"
