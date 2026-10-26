extends "res://scripts/effects/card_effect.gd"
## 1-063 enter-the-field ability


func when_enter_field(ctx) -> void:
	if await ctx.may("Play a Forward"):
		await ctx.play_from_hand({"is_type": "Forward", "element": "風", "is_cost_lower_than": 4})
