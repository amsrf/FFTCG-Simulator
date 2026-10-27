extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-164 Tidus: when it attacks, your Water Forwards gain +1000.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ATTACK: Callable(self, "when_attack"),
	}


func when_attack(ctx) -> void:
	ctx.power_change(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR).of_element("水")), 1000, 1)
