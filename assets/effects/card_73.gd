extends "res://scripts/effects/card_effect.gd"

func damage_caused_riders() -> Array:
	return [{
		"status": "cid_verdict",
		"duration": 1,
		# The method on THIS card's effect the engine calls when the marked Forward reaches the Break Zone this turn
		# (Game._trigger_status_break_zone_effects). Looked up by card id, so it works after Cid has left the field.
		"on_enter_break_zone": "marked_card_to_break_zone",
	}]


## The marked Forward was put into the Break Zone this turn: Cid's controller's opponent mills 2.
func marked_card_to_break_zone(ctx: EFFECT_CONTEXT) -> void:
	await ctx.opponent_mills(2)
