extends "res://scripts/effects/card_effect.gd"
## 1-055: when it enters the Break Zone from the field, its controller takes 1 damage.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_BREAK_FROM_FIELD: Callable(self, "when_enter_break_from_field"),
	}


func when_enter_break_from_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.take_damage_to_controller(1)
