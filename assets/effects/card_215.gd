extends "res://scripts/effects/card_effect.gd"

func handlers() -> Dictionary:
	return {
		EVENTS.Event.SUMMON_CAST: Callable(self, "summon_cast"),
	}


func event_matches(event: int, source: Card, data: Dictionary) -> bool:
	if event != EVENTS.Event.SUMMON_CAST:
		return false
	var event_card: Card = data.get("card")
	return event_card != null and is_instance_valid(event_card) \
		and event_card.controller != source.controller


func summon_cast(ctx: EFFECT_CONTEXT) -> void:
	ctx.untap([ctx.source])
