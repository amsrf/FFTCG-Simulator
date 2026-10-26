extends "res://scripts/effects/card_effect.gd"
## 1-043H Snow


func when_attack(ctx) -> void:
	var targets: Array = await ctx.choose_targets({
		"is_type": "Forward", "controller": "opponent",
	})
	if targets.is_empty():
		return
	ctx.dull(targets)
	if ctx.condition("cast_this_turn:Shiva"):
		ctx.add_status(targets, "frozen", 1)
