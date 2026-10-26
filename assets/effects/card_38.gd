extends "res://scripts/effects/card_effect.gd"
## 1-038R Shiva


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward"}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Forward"})
	if targets.is_empty():
		return
	ctx.dull(targets)
	ctx.add_status(targets, "frozen", 1)
