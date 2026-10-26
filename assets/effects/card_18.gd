extends "res://scripts/effects/card_effect.gd"
## 1-018L Bahamut


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward", "controller": "opponent", "count": 2}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({
		"is_type": "Forward", "controller": "opponent", "count": 2,
	})
	if targets.is_empty():
		return
	ctx.add_status(targets, "fragile", 1)
	ctx.damage(targets, 10000)
