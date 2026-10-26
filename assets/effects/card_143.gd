extends "res://scripts/effects/card_effect.gd"
## 1-143C Ramuh


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward", "is_tapped": false}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Forward", "is_tapped": false})
	ctx.damage(targets, 5000)
