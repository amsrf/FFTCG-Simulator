extends "res://scripts/effects/card_effect.gd"
## 1-172C Moogle


func when_cast(ctx) -> void:
	ctx.draw(ctx.owner_id, 2)
	await ctx.discard(ctx.owner_id, 1)
