extends "res://scripts/effects/card_effect.gd"
## 12-027C Gunbreaker
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func when_party_attack(ctx) -> void:
	await ctx.opponent_discards(1)
