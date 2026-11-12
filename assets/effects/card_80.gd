extends "res://scripts/effects/card_effect.gd"
## 1-080 enter-the-field ability


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	ctx.untap_all_matching(CARD_QUERY.new().character(true).controlled_by(CARD_QUERY.Controller.YOUR).of_element("風"))


func ex_burst_event() -> int:
	return EVENTS.Event.ENTER_FIELD
