extends "res://scripts/effects/card_effect.gd"
## 1-133 enter-the-field ability


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.break_zone_to_hand(CARD_QUERY.new().any_of([CARD_QUERY.new().of_type("Forward"), CARD_QUERY.new().of_type("Backup")]))
