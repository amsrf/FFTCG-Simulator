extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-110C Titan


func cast_target_criteria(_ctx) -> Variant:
	return TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.PLAYER))


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.PLAYER)))
	if targets.is_empty():
		return
	ctx.dull(targets)
	ctx.add_status(targets, "unbreakable", 1)
