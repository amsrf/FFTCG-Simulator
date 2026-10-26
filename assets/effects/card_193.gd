extends "res://scripts/effects/card_effect.gd"
## 1-193S Jihl Nabaat


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"}, 2)
	ctx.add_status(targets, "frozen", 1)


func ex_burst_event() -> String:
	return "when_enter_field"
