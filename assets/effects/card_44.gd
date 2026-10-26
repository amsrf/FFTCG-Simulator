extends "res://scripts/effects/card_effect.gd"
## 1-044 enter-the-field ability


func when_enter_field(ctx) -> void:
	await ctx.each_player_discards(2)
