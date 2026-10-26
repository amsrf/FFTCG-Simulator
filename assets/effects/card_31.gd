extends "res://scripts/effects/card_effect.gd"
## 1-031C Chemist


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"})
	if targets.is_empty():
		return
	ctx.dull(targets)
