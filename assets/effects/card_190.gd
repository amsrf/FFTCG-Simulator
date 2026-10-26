extends "res://scripts/effects/card_effect.gd"
## 1-190S Bahamut Fury


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward"}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Forward"})
	if targets.is_empty():
		return
	var discarded: int = 0
	if await ctx.may("Discard 1"):
		discarded = await ctx.discard(ctx.owner_id, 1)
	ctx.damage(targets, 7000 if discarded > 0 else 5000)


func ex_burst_event() -> String:
	return "when_cast"
