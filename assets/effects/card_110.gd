extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-110C Titan


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.CAST, "when_cast"),
	]


func cast_target_criteria(_ctx: EFFECT_CONTEXT) -> Variant:
	return TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.PLAYER))


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.cast_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.PLAYER)))
	if targets.is_empty():
		return
	ctx.dull(targets)
	ctx.add_status(targets, "unbreakable", 1)
