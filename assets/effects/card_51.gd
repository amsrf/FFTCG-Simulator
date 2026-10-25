extends "res://scripts/effects/card_effect.gd"
## 1-051R Nooj
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func event_specs() -> Array:
	return [_event("when_enter_field", Callable(self, "_on_enter_field"))]


func _on_enter_field(ctx) -> void:
	await ctx.opponent_discards(1)
