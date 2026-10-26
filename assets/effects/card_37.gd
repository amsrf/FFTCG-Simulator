extends "res://scripts/effects/card_effect.gd"
## 1-037 Kuja: when chosen by the opponent, they discard 1.


func when_chosen(ctx) -> void:
	await ctx.opponent_discards(1)
