extends "res://scripts/effects/card_effect.gd"
## 1-185 The Emperor: from the Break Zone, you may search it out and play it dull.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_BREAK_FROM_FIELD, "when_enter_break_from_field"),
	]


func when_enter_break_from_field(ctx: EFFECT_CONTEXT) -> void:
	if await ctx.may("Play The Emperor"):
		await ctx.search_deck(CARD_QUERY.new().named("The Emperor"),  "field_dull",  true)
