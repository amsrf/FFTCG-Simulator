extends "res://scripts/effects/card_effect.gd"
## 21-021C Red Mage


func when_party_attack(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_character": true})
	if targets.is_empty():
		return
	ctx.dull(targets)
	ctx.add_status(targets, "frozen", 1)
