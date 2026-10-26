extends "res://scripts/effects/card_effect.gd"
## 1-060 enter-the-field ability


func when_enter_field(ctx) -> void:
	if await ctx.may_for(3 - ctx.owner_id, "Play a Character"):
		await ctx.play_from_hand({"is_character": true}, "opponent")
