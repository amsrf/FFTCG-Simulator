extends "res://scripts/effects/card_effect.gd"
## 1-077 enter-the-field ability


func when_enter_field(ctx) -> void:
	await ctx.play_from_break_zone({"is_type": "Forward", "is_cost_lower_than": 3})
