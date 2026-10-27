extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-001H Auron


func when_cause_damage_to_player(ctx) -> void:
	await ctx.may_play_from_hand(CARD_QUERY.new().of_type("Backup").of_element("火"),  true,  "Play a Fire Backup")
