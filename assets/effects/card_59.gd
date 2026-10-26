extends "res://scripts/effects/card_effect.gd"
## 1-059R Laguna


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward", "controller": "opponent"})
	if targets.is_empty():
		return
	ctx.dull(targets)
	if ctx.condition("controls:Squall"):
		ctx.add_status(targets, "frozen", 1)


func ex_burst_event() -> String:
	return "when_enter_field"
