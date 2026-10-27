extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-012R Zack


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)))
	if targets.is_empty():
		return
	ctx.damage(targets, 2000)

func conditional_powers() -> Array:
	return [{"value": 2000, "condition": Callable(self, "_has_aerith")}]


func _has_aerith(source: Card) -> bool:
	return controls(source, {"is_named": "Aerith"})
