extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-190S Bahamut Fury


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAST: Callable(self, "when_cast"),
	}


func cast_target_criteria(_ctx) -> Variant:
	return TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")))
	if targets.is_empty():
		return
	var discarded: int = 0
	if await ctx.may("Discard 1"):
		discarded = await ctx.discard(ctx.owner_id, 1)
	ctx.damage(targets, 7000 if discarded > 0 else 5000)


func ex_burst_event() -> int:
	return EVENTS.Event.CAST
