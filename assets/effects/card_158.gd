extends "res://scripts/effects/card_effect.gd"
## 1-158 enter-the-field ability


func when_enter_field(ctx) -> void:
	var keep: Array = []
	var mine: Card = await ctx.choose(
		ctx.cards_in("field", {"is_type": "Forward", "controller": "your"}),
		"Choose a Forward to keep")
	if mine != null:
		keep.append(mine)
	var theirs: Card = await ctx.choose_for(3 - ctx.owner_id,
		ctx.cards_in("field", {"is_type": "Forward", "controller": "theirs"}),
		"Choose a Forward to keep")
	if theirs != null:
		keep.append(theirs)
	var rest: Array = ctx.cards_in("field", {"is_type": "Forward"}).filter(
		func(c): return not keep.has(c))
	ctx.break_cards(rest)
