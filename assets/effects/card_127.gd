extends "res://scripts/effects/card_effect.gd"
## 1-127H Kain


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"})
	if targets.is_empty():
		return
	ctx.power_change(targets, -5000, 1)


func ex_burst_event() -> String:
	return "when_enter_field"
