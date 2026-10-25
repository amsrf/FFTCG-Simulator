extends "res://scripts/effects/card_effect.gd"
## 1-033C Argath
##
## Migrated from the JSON path.


func triggered_events() -> Array[String]:
	return ["when_enter_field"]


func on_enter_field(ctx) -> void:
	await ctx.opponent_discards(1)
