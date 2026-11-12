extends "res://scripts/effects/card_effect.gd"
## 1-202S Vincent
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ATTACK, "when_attack"),
	]


func when_attack(ctx: EFFECT_CONTEXT) -> void:
	ctx.add_status([ctx.source], "first_strike", 1)
