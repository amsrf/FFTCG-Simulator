extends "res://scripts/effects/card_effect.gd"
## 12-053C Boko
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.PARTY_DEALS_DAMAGE: Callable(self, "when_party_deals_damage"),
	}


func when_party_deals_damage(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 1)
