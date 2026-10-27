extends "res://scripts/effects/card_effect.gd"
## 1-168: when it enters the Break Zone from the field, draw 1.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_BREAK_FROM_FIELD: Callable(self, "when_enter_break_from_field"),
	}


func when_enter_break_from_field(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 1)
