extends "res://scripts/effects/card_effect.gd"
## 1-101 enter-the-field ability


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	ctx.power_change(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR)), 4000, 1)


func ex_burst_event() -> int:
	return EVENTS.Event.ENTER_FIELD
