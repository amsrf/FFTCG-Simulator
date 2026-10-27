extends "res://scripts/effects/card_effect.gd"
## 12-027C Gunbreaker
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.PARTY_ATTACK: Callable(self, "when_party_attack"),
	}


func when_party_attack(ctx) -> void:
	await ctx.opponent_discards(1)
