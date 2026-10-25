extends "res://scripts/effects/card_effect.gd"
## 1-033C Argath
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func when_enter_field(ctx) -> void:
	await ctx.opponent_discards(1)
