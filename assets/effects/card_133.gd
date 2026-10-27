extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-133 enter-the-field ability


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.break_zone_to_hand(CARD_QUERY.new().any_of([CARD_QUERY.new().of_type("Forward"), CARD_QUERY.new().of_type("Backup")]))
