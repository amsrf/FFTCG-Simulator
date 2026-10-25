extends "res://scripts/effects/card_effect.gd"
## 12-053C Boko
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func event_specs() -> Array:
	return [_event("when_party_deals_damage", Callable(self, "_on_party_deals_damage"))]


func _on_party_deals_damage(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
