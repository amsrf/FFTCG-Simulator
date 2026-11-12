extends "res://scripts/effects/card_effect.gd"
## 1-168: when it enters the Break Zone from the field, draw 1.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_BREAK_FROM_FIELD, "when_enter_break_from_field"),
	]


func when_enter_break_from_field(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 1)
