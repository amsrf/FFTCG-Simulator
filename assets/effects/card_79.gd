extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-079 enter-the-field ability


func when_enter_field(ctx) -> void:
	await ctx.search_deck(CARD_QUERY.new().named("Hope"))


func ex_burst_event() -> String:
	return "when_enter_field"
