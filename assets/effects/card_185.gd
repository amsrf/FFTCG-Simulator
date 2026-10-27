extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-185 The Emperor: from the Break Zone, you may search it out and play it dull.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_BREAK_FROM_FIELD: Callable(self, "when_enter_break_from_field"),
	}


func when_enter_break_from_field(ctx: EFFECT_CONTEXT) -> void:
	if await ctx.may("Play The Emperor"):
		await ctx.search_deck(CARD_QUERY.new().named("The Emperor"),  "field_dull",  true)
