extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-158 enter-the-field ability


func when_enter_field(ctx) -> void:
	var keep: Array = []
	var mine: Card = await ctx.choose(
		ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR)),
		"Choose a Forward to keep")
	if mine != null:
		keep.append(mine)
	var theirs: Card = await ctx.choose_for(3 - ctx.owner_id,
		ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)),
		"Choose a Forward to keep")
	if theirs != null:
		keep.append(theirs)
	var rest: Array = ctx.cards_in("field", CARD_QUERY.new().of_type("Forward")).filter(
		func(c): return not keep.has(c))
	ctx.break_cards(rest)
