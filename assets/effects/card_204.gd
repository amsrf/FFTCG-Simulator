extends "res://scripts/effects/card_effect.gd"
## 1-204 enter-the-field ability


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.search_deck(CARD_QUERY.new().of_category("VII").of_type("Forward"))
