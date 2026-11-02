extends "res://scripts/effects/card_effect.gd"

func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.SUMMON_CAST, "summon_cast").card(
			CARD_QUERY.new().controlled_by(CARD_QUERY.Controller.OPPONENT)),
	]


func summon_cast(ctx: EFFECT_CONTEXT) -> void:
	ctx.untap([ctx.source])
