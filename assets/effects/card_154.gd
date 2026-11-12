extends "res://scripts/effects/card_effect.gd"
## 1-154 enter-the-field ability


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
		trigger(EVENTS.Event.PARTY_ATTACK, "when_party_attack"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 1)

func when_party_attack(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 1)
	await ctx.discard(ctx.owner_id, 1)
