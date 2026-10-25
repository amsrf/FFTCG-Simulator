extends "res://scripts/effects/card_effect.gd"
## 1-021H Firion
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func event_specs() -> Array:
	return [_event("when_enter_field", Callable(self, "_on_enter_field"))]


func _on_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"}, 1)
	if targets.is_empty():
		return
	ctx.damage(targets, 4000)
