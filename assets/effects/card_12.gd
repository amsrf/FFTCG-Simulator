extends "res://scripts/effects/card_effect.gd"
## 1-012R Zack


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward", "controller": "opponent"})
	if targets.is_empty():
		return
	ctx.damage(targets, 2000)
