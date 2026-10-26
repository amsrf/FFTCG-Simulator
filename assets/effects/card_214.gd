extends "res://scripts/effects/card_effect.gd"

func event_matches(event: String, source: Card, data: Dictionary) -> bool:
	if event != "summon_cast" or source.tapped:
		return false
	var event_card: Card = data.get("card")
	return event_card != null and is_instance_valid(event_card) \
		and event_card.controller == source.controller


func summon_cast(ctx) -> void:
	var turn: int = int(ctx.game.get("turn_number")) if ctx.game != null else 0
	if not ctx.source.claim_event_once("yuna_summon_draw", turn):
		return
	if not await ctx.may("Dull Yuna to draw 1"):
		return
	ctx.dull([ctx.source])
	ctx.draw(ctx.owner_id, 1)
