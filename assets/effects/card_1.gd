extends "res://scripts/effects/card_effect.gd"
## 1-001H Auron


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.CAUSE_DAMAGE_TO_PLAYER, "when_cause_damage_to_player"),
	]


func when_cause_damage_to_player(ctx: EFFECT_CONTEXT) -> void:
	await ctx.may_play_from_hand(CARD_QUERY.new().of_type("Backup").of_element("火"),  true,  "Play a Fire Backup")
