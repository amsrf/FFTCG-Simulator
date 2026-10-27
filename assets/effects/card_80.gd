extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-080 enter-the-field ability


func when_enter_field(ctx) -> void:
	ctx.untap_all_matching(CARD_QUERY.new().character(true).controlled_by(CARD_QUERY.Controller.YOUR).of_element("風"))


func ex_burst_event() -> String:
	return "when_enter_field"
