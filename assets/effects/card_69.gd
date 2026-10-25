extends "res://scripts/effects/card_effect.gd"
## 1-069C Thief
##
## Migrated from the JSON path.


func triggered_events() -> Array[String]:
	return ["when_enter_field"]


func on_enter_field(ctx) -> void:
	await ctx.mill(3 - ctx.owner_id, 1)
