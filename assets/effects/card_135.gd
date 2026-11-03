extends "res://scripts/effects/card_effect.gd"
const SELECTION_REQUEST := preload("res://scripts/effects/selection_request.gd")
## 1-135L Golbez
##
## When Golbez is put from the field into the Break Zone, you may search for up to 4 Forwards of cost 2, each of a
## different Element, and play them onto the field. Their auto-abilities will not trigger.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_BREAK_FROM_FIELD, "when_enter_break_from_field"),
	]


func when_enter_break_from_field(ctx: EFFECT_CONTEXT) -> void:
	if not await ctx.may("Search for up to 4 Forwards of cost 2"):
		return
	var request = SELECTION_REQUEST.new(
		CARD_QUERY.new().of_type("Forward").cost_at_least(2).cost_at_most(2)
	).up_to(4).unique("element")
	await ctx.search_deck_multi(
		request,
		"field",
		true,
		"Choose up to 4 Forwards of cost 2, each of a different Element")
