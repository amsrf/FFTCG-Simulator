extends "res://scripts/effects/card_effect.gd"
## 1-090R Rikku
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func event_specs() -> Array:
	return [_event("when_enter_field", Callable(self, "_on_enter_field"))]


func _on_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Backup", "controller": "player"}, 5)
	if targets.is_empty():
		return
	await ctx.return_to_hand(targets)
