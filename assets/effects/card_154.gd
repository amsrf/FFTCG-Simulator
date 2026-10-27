extends "res://scripts/effects/card_effect.gd"
## 1-154 enter-the-field ability


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
		EVENTS.Event.PARTY_ATTACK: Callable(self, "when_party_attack"),
	}


func when_enter_field(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)

func when_party_attack(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
	await ctx.discard(ctx.owner_id, 1)
