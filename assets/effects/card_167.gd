extends "res://scripts/effects/card_effect.gd"
## 1-167C Viking
##
## Migrated from the JSON path.


func triggered_events() -> Array[String]:
	return ["when_enter_field"]


func on_enter_field(ctx) -> void:
	ctx.draw(ctx.owner_id, 1)
