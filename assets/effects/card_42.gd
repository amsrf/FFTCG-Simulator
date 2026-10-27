extends "res://scripts/effects/card_effect.gd"
## 1-042 enter-the-field ability


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	await ctx.each_player_discards(1)
	if ctx.condition("controls:Laguna"):
		await ctx.opponent_discards(1)

func conditional_powers() -> Array:
	return [{"value": 3000, "condition": Callable(self, "_has_laguna")}]


func _has_laguna(source: Card) -> bool:
	return controls(source, {"is_named": "Laguna"})
