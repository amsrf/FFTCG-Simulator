extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-109 enter-the-field ability


func when_enter_field(ctx) -> void:
	await ctx.choose_break_zone_card(CARD_QUERY.new().of_type("Forward"),  "self",  "Choose a Forward in your Break Zone")
	await ctx.choose_break_zone_card(CARD_QUERY.new().of_type("Forward"),  "opponent",  "Choose a Forward in your Break Zone")
	await ctx.put_card_into_hand()


func ex_burst_event() -> String:
	return "when_enter_field"
