extends "res://scripts/effects/card_effect.gd"
## 13-095C Tonogiri
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func event_specs() -> Array:
	return [_event("when_party_attack", Callable(self, "_on_party_attack"))]


func _on_party_attack(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"}, 1)
	if targets.is_empty():
		return
	await ctx.return_to_hand(targets)
