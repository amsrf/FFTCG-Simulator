extends "res://scripts/effects/card_effect.gd"
## 1-192S Cid Raines


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({
		"is_type": "Forward", "controller": "opponent", "is_tapped": false,
	})
	if targets.is_empty():
		return
	ctx.damage(targets, 4000)
