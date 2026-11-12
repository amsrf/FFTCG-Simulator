extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-190S Bahamut Fury


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.CAST, "when_cast"),
	]


func cast_target_criteria(_ctx: EFFECT_CONTEXT) -> Variant:
	return TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.cast_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")))
	if targets.is_empty():
		return
	var discarded: int = 0
	if await ctx.may("Discard 1"):
		discarded = await ctx.discard(ctx.owner_id, 1)
	ctx.damage(targets, 7000 if discarded > 0 else 5000)


func ex_burst_event() -> int:
	return EVENTS.Event.CAST
