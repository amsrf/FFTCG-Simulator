extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-018L Bahamut


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAST: Callable(self, "when_cast"),
	}


func cast_target_criteria(_ctx: EFFECT_CONTEXT) -> Variant:
	return TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)).up_to(2)


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.cast_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)).up_to(2))
	if targets.is_empty():
		return
	ctx.add_status(targets, "fragile", 1)
	ctx.damage(targets, 10000)
