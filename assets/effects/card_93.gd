extends "res://scripts/effects/card_effect.gd"
## 1-093 Vanille: search for Hecatoncheir, then return this card to the field.


func when_enter_break_from_field(ctx) -> void:
	await ctx.search_deck({"is_named": "Hecatoncheir"}, "removed")
	if ctx.condition("if_last_succeeded"):
		await ctx.return_from_break_zone(true)
