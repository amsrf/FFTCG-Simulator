extends "res://scripts/effects/card_effect.gd"
## 1-077 enter-the-field ability


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.play_from_break_zone(CARD_QUERY.new().of_type("Forward").where({"is_cost_lower_than": 3}))
