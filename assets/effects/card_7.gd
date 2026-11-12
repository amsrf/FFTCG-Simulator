extends "res://scripts/effects/card_effect.gd"
## 1-007 Gadot. Two separate enter-the-field auto-abilities, so entering puts TWO stack objects on the stack.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "play_fire_forward"),
		trigger(EVENTS.Event.ENTER_FIELD, "pump_forwards"),
	]


## "When Gadot enters the field, you may play 1 Fire Forward of cost 2 or less from your hand onto the field."
func play_fire_forward(ctx: EFFECT_CONTEXT) -> void:
	await ctx.may_play_from_hand(CARD_QUERY.new().of_type("Forward").of_element("火").cost_at_most(2),
		false, "Play a Fire Forward of cost 2 or less")


## "When Gadot enters the field, all the Forwards you control gain +1000 power until the end of the turn."
func pump_forwards(ctx: EFFECT_CONTEXT) -> void:
	ctx.power_change(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR)), 1000, 1)
