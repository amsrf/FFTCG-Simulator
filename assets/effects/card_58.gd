extends "res://scripts/effects/card_effect.gd"
## 1-058L Laguna


func when_cause_damage_to_player(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward", "is_tapped": true})
	if targets.is_empty():
		return
	if await ctx.may("Deal 7000"):
		ctx.damage(targets, 7000)
