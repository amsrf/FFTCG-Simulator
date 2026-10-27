extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-038R Shiva


func cast_target_criteria(_ctx) -> Variant:
	return TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")))
	if targets.is_empty():
		return
	ctx.dull(targets)
	ctx.add_status(targets, "frozen", 1)


func ex_burst_event() -> String:
	return "when_cast"
