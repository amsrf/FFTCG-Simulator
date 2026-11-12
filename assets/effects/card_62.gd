extends "res://scripts/effects/card_effect.gd"
## 1-062L Valefor


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.CAST, "when_cast"),
	]


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	await ctx.return_to_hand(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward")))
