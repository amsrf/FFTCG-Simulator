extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-079 enter-the-field ability


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.search_deck(CARD_QUERY.new().named("Hope"))


func ex_burst_event() -> int:
	return EVENTS.Event.ENTER_FIELD
