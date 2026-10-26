extends "res://scripts/effects/card_effect.gd"
## 1-118R Mustadio


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward", "is_tapped": true})
	if targets.is_empty():
		return
	ctx.break_cards(targets)
