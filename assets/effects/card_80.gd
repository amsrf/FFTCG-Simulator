extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-080 enter-the-field ability


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx) -> void:
	ctx.untap_all_matching(CARD_QUERY.new().character(true).controlled_by(CARD_QUERY.Controller.YOUR).of_element("風"))


func ex_burst_event() -> int:
	return EVENTS.Event.ENTER_FIELD
