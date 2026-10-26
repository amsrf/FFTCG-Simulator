extends "res://scripts/effects/card_effect.gd"
## 1-062L Valefor


func when_cast(ctx) -> void:
	await ctx.return_to_hand(ctx.cards_in("field", {"is_type": "Forward"}))
