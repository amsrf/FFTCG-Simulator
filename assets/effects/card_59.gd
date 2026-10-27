extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-059R Laguna


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)))
	if targets.is_empty():
		return
	ctx.dull(targets)
	if ctx.condition("controls:Squall"):
		ctx.add_status(targets, "frozen", 1)


func ex_burst_event() -> String:
	return "when_enter_field"

func conditional_powers() -> Array:
	return [{"value": 2000, "condition": Callable(self, "_has_squall")}]


func _has_squall(source: Card) -> bool:
	return controls(source, {"is_named": "Squall"})
