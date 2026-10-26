extends "res://scripts/effects/card_effect.gd"
## 9-006H Queen of Eblan


func when_party_attack(ctx) -> void:
	if not ctx.condition("party_has_named:King of Eblan"):
		return
	var targets: Array = await ctx.choose_targets({
		"is_type": "Forward", "controller": "opponent",
	})
	if targets.is_empty():
		return
	ctx.damage(targets, 5000)
