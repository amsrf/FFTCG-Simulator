extends "res://scripts/effects/card_effect.gd"
## 1-140C Magus
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"}, 1)
	if targets.is_empty():
		return
	ctx.damage(targets, 5000)
