extends "res://scripts/effects/card_effect.gd"
## 1-194S Snow


func when_blocks(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"})
	ctx.dull(targets)
