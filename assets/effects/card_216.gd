extends "res://scripts/effects/card_effect.gd"
## 1-216S Wakka


func when_attack(ctx) -> void:
	var targets: Array = await ctx.choose_targets({
		"is_type": "Forward", "controller": "your",
	})
	if targets.is_empty():
		return
	var forwards: int = ctx.cards_in("field", {
		"is_type": "Forward", "controller": "your",
	}).size()
	ctx.power_change(targets, forwards * 1000, 1)
