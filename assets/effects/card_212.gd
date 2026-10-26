extends "res://scripts/effects/card_effect.gd"
## 1-212S Shuyin


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({
		"is_type": "Forward", "controller": "opponent", "is_cost_at_most": 3,
	})
	await ctx.return_to_hand(targets)


func ex_burst_event() -> String:
	return "when_enter_field"
