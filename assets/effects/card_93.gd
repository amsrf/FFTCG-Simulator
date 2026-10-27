extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-093 Vanille: search for Hecatoncheir, then return this card to the field.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_BREAK_FROM_FIELD: Callable(self, "when_enter_break_from_field"),
	}


func when_enter_break_from_field(ctx) -> void:
	await ctx.search_deck(CARD_QUERY.new().named("Hecatoncheir"),  "removed")
	if ctx.condition("if_last_succeeded"):
		await ctx.return_from_break_zone(true)
