extends "res://scripts/effects/card_effect.gd"
## TEST ONLY (break_zone_probe): a card effect with BOTH Break Zone abilities, so the probe can tell which of them the
## engine fires in each case. No real card has both. The handlers do nothing: the probe watches what reaches the stack.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_BREAK_FROM_FIELD, "when_enter_break_from_field"),
		trigger(EVENTS.Event.BREAK, "when_break"),
	]


func when_enter_break_from_field(_ctx: EFFECT_CONTEXT) -> void:
	pass


func when_break(_ctx: EFFECT_CONTEXT) -> void:
	pass
