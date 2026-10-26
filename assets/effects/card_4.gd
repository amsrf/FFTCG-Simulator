extends "res://scripts/effects/card_effect.gd"
## 1-004C Ifrit


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward"}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Forward"})
	ctx.damage(targets, 4000)
