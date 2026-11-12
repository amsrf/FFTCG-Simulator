extends "res://scripts/effects/card_effect.gd"
## 1-037 Kuja: when chosen by the opponent, they discard 1.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.CHOSEN, "when_chosen"),
	]


func when_chosen(ctx: EFFECT_CONTEXT) -> void:
	await ctx.opponent_discards(1)
