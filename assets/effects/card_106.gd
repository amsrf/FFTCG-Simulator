extends "res://scripts/effects/card_effect.gd"
## 1-106C Golem


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward"}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Forward"})
	if targets.is_empty():
		return
	var blocking: bool = targets[0].status_effects.has("blocking")
	ctx.power_change(targets, 4000 if blocking else 2000, 1)


func ex_burst_event() -> String:
	return "when_cast"
