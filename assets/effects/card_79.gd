extends "res://scripts/effects/card_effect.gd"
## 1-079 enter-the-field ability


func when_enter_field(ctx) -> void:
	await ctx.search_deck({"is_named": "Hope"})


func ex_burst_event() -> String:
	return "when_enter_field"
