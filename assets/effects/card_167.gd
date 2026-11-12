extends "res://scripts/effects/card_effect.gd"
## 1-167C Viking
##
## Auto-ability: targets, if any, are chosen when the ability resolves.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 1)
