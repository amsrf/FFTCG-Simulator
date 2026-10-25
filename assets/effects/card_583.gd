extends "res://scripts/effects/card_effect.gd"
## 12-087H Mid Previa
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func when_party_attacks(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward", "controller": "opponent", "is_tapped": false}, 1)
	if targets.is_empty():
		return
	ctx.damage(targets, 8000)
