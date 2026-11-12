extends "res://scripts/effects/card_effect.gd"
## 1-109 enter-the-field ability


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.choose_break_zone_card(CARD_QUERY.new().of_type("Forward"),  "self",  "Choose a Forward in your Break Zone")
	await ctx.choose_break_zone_card(CARD_QUERY.new().of_type("Forward"),  "opponent",  "Choose a Forward in your Break Zone")
	await ctx.put_card_into_hand()


func ex_burst_event() -> int:
	return EVENTS.Event.ENTER_FIELD
