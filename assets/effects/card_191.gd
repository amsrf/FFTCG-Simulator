extends "res://scripts/effects/card_effect.gd"
## 1-191S Red XIII


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"})
	ctx.power_change(targets, 3000, 1)
