extends "res://scripts/effects/card_effect.gd"
## 1-186L Sephiroth


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Backup"})
	if targets.is_empty():
		return
	ctx.break_cards(targets)


func keywords() -> Array[String]:
	return ["first_strike"]
