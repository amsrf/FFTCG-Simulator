extends "res://scripts/effects/card_effect.gd"
## 1-069C Thief
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func when_enter_field(ctx) -> void:
	await ctx.mill(3 - ctx.owner_id, 1)
