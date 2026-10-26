extends "res://scripts/effects/card_effect.gd"
## 1-039C Shiva


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward", "is_tapped": true}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Forward", "is_tapped": true})
	ctx.damage(targets, 5000)
