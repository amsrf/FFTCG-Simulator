extends "res://scripts/effects/card_effect.gd"
## 1-176H Yuna


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"})
	await ctx.return_to_hand(targets)


func ex_burst_event() -> String:
	return "when_enter_field"

func static_rules() -> Dictionary:
	return {"break_zone_exile": true}
