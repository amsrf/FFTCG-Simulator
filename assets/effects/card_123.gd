extends "res://scripts/effects/card_effect.gd"
## 1-123R Odin


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward", "is_cost_at_most": 4}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Forward", "is_cost_at_most": 4})
	if targets.is_empty():
		return
	ctx.break_cards(targets)
