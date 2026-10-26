extends "res://scripts/effects/card_effect.gd"
## 1-188R Zangan


func auras() -> Array:
	return [
		_aura({
			"targets": {"is_type": "Forward", "controller": "player", "is_named": "Tifa", "is_cost_at_most": 4},
			"method": "grant_status",
			"status": "haste",
		}),
	]


func ex_burst_event() -> String:
	return "when_enter_field"

func when_enter_field(ctx) -> void:
	await ctx.search_deck({"name": "Tifa"})
