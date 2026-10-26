extends "res://scripts/effects/card_effect.gd"
## 1-110C Titan


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward", "controller": "player"}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Forward", "controller": "player"})
	if targets.is_empty():
		return
	ctx.dull(targets)
	ctx.add_status(targets, "unbreakable", 1)
