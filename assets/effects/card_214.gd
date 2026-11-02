extends "res://scripts/effects/card_effect.gd"

func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.SUMMON_CAST, "summon_cast")
			.card(CARD_QUERY.new().controlled_by(CARD_QUERY.Controller.YOUR))
			.active_only(),
	]


func summon_cast(ctx: EFFECT_CONTEXT) -> void:
	var turn: int = ctx.turn_number()
	if not ctx.source.claim_event_once("yuna_summon_draw", turn):
		return
	if not await ctx.may("Dull Yuna to draw 1"):
		return
	ctx.dull([ctx.source])
	ctx.draw(ctx.owner_id, 1)
