extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-038R Shiva


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAST: Callable(self, "when_cast"),
	}


func cast_target_criteria(_ctx: EFFECT_CONTEXT) -> Variant:
	return TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.cast_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")))
	if targets.is_empty():
		return
	ctx.dull(targets)
	ctx.add_status(targets, "frozen", 1)


func ex_burst_event() -> int:
	return EVENTS.Event.CAST
