extends "res://scripts/effects/card_effect.gd"
## 1-061R Alexander


func cast_target_criteria(_ctx) -> Variant:
	return {"is_type": "Forward", "is_cost_at_least": 5}


func when_cast(ctx) -> void:
	var targets: Array = await ctx.cast_targets({"is_type": "Forward", "is_cost_at_least": 5})
	if targets.is_empty():
		return
	ctx.break_cards(targets)


func ex_burst_event() -> String:
	return "when_cast"
