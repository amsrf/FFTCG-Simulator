extends "res://scripts/effects/card_effect.gd"
## 1-064R Aerith


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({
		"is_type": "Backup",
		"exclude": {"is_named": "Aerith"},
	}, 3)
	ctx.untap(targets)
