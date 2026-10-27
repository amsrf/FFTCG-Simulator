extends "res://scripts/effects/card_effect.gd"
## 1-044 enter-the-field ability


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.each_player_discards(2)


func keywords() -> Array[String]:
	return ["first_strike"]
