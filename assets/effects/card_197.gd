extends "res://scripts/effects/card_effect.gd"
## 1-197 enter-the-field ability


func when_enter_field(ctx) -> void:
	await ctx.search_deck({"category": "X", "type": "Forward"})
