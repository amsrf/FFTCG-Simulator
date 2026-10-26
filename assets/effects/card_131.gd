extends "res://scripts/effects/card_effect.gd"
## 1-131R Cait Sith


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Backup", "is_cost_at_most": 1})
	if targets.is_empty():
		return
	ctx.break_cards(targets)
