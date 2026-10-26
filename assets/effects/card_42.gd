extends "res://scripts/effects/card_effect.gd"
## 1-042 enter-the-field ability


func when_enter_field(ctx) -> void:
	await ctx.each_player_discards(1)
	if ctx.condition("controls:Laguna"):
		await ctx.opponent_discards(1)
