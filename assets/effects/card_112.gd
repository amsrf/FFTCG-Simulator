extends "res://scripts/effects/card_effect.gd"
## 1-112R Delita


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_character": true, "controller": "player"})
	if targets.is_empty():
		return
	ctx.break_cards(targets)
