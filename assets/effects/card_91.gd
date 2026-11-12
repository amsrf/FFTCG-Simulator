extends "res://scripts/effects/card_effect.gd"
## 1-091 enter-the-field ability


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.search_deck(CARD_QUERY.new().any_of([CARD_QUERY.new().name_contains("Lightning"), CARD_QUERY.new().name_contains("Snow")]))


func ex_burst_event() -> int:
	return EVENTS.Event.ENTER_FIELD
