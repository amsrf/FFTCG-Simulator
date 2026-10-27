extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-185 The Emperor: from the Break Zone, you may search it out and play it dull.


func when_enter_break_from_field(ctx) -> void:
	if await ctx.may("Play The Emperor"):
		await ctx.search_deck(CARD_QUERY.new().named("The Emperor"),  "field_dull",  true)
