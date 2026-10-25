extends "res://scripts/effects/card_effect.gd"
## 1-065C Aerith
##
## Migrated from the JSON path.


func target_criteria(_event: String):
	return {"is_type": "Backup", "controller": "player"}


func triggered_events() -> Array[String]:
	return ["when_enter_field"]


func on_enter_field(ctx) -> void:
	var target: Card = ctx.targets[0] if not ctx.targets.is_empty() else null
	if target != null:
		ctx.untap([target])
