extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-061R Alexander


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAST: Callable(self, "when_cast"),
	}


func cast_target_criteria(_ctx: EFFECT_CONTEXT) -> Variant:
	return TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").cost_at_least(5))


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.cast_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").cost_at_least(5)))
	if targets.is_empty():
		return
	ctx.break_cards(targets)


func ex_burst_event() -> int:
	return EVENTS.Event.CAST
