extends "res://scripts/effects/card_effect.gd"

func handlers() -> Dictionary:
	return {
		EVENTS.Event.SUMMON_CAST: Callable(self, "summon_cast"),
	}


func event_matches(event: int, source: Card, data: Dictionary) -> bool:
	if event != EVENTS.Event.SUMMON_CAST or source.tapped:
		return false
	var event_card: Card = data.get("card")
	return event_card != null and is_instance_valid(event_card) \
		and event_card.controller == source.controller


func summon_cast(ctx: EFFECT_CONTEXT) -> void:
	var turn: int = ctx.turn_number()
	if not ctx.source.claim_event_once("yuna_summon_draw", turn):
		return
	if not await ctx.may("Dull Yuna to draw 1"):
		return
	ctx.dull([ctx.source])
	ctx.draw(ctx.owner_id, 1)
