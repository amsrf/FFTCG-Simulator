extends "res://scripts/effects/card_effect.gd"

func event_matches(event: String, source: Card, data: Dictionary) -> bool:
	if event != "summon_cast":
		return false
	var event_card: Card = data.get("card")
	return event_card != null and is_instance_valid(event_card) \
		and event_card.controller != source.controller


func summon_cast(ctx) -> void:
	ctx.untap([ctx.source])
