extends "res://scripts/effects/card_effect.gd"
## 1-070C Thief
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func event_specs() -> Array:
	return [_event("when_enter_field", Callable(self, "_on_enter_field"))]


func _on_enter_field(ctx) -> void:
	await ctx.mill(3 - ctx.owner_id, 1)
