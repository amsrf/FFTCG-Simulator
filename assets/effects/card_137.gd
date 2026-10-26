extends "res://scripts/effects/card_effect.gd"
## 1-137R Seymour


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward", "is_cost_at_most": 3})
	if targets.is_empty():
		return
	ctx.break_cards(targets)
