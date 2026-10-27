extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-007 enter-the-field ability


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	ctx.power_change(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR)), 1000, 1)
