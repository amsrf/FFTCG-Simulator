extends "res://scripts/effects/card_effect.gd"
## 1-179: when this card deals damage to the opponent, draw 1.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.CAUSE_DAMAGE_TO_PLAYER, "when_cause_damage_to_player"),
	]


func when_cause_damage_to_player(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 1)
