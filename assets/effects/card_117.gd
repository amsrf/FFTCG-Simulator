extends "res://scripts/effects/card_effect.gd"
## 1-117R Hecatoncheir


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Backup", "is_cost_at_least": 3}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Backup", "is_cost_at_least": 3})
	if targets.is_empty():
		return
	ctx.break_cards(targets)
