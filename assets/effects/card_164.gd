extends "res://scripts/effects/card_effect.gd"
## 1-164 Tidus: when it attacks, your Water Forwards gain +1000.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ATTACK, "when_attack"),
	]


func when_attack(ctx: EFFECT_CONTEXT) -> void:
	ctx.power_change(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR).of_element("水")), 1000, 1)
