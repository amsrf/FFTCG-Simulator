extends "res://scripts/effects/card_effect.gd"
## 12-027C Gunbreaker
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func event_specs() -> Array:
	return [_event("when_party_attack", Callable(self, "_on_party_attack"))]


func _on_party_attack(ctx) -> void:
	await ctx.opponent_discards(1)
