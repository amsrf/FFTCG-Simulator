extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-009C Cloud


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)))
	if targets.is_empty():
		return
	ctx.damage(targets, 2000)

func conditional_powers() -> Array:
	return [{"value": 2000, "condition": Callable(self, "_has_category_vii")}]


func _has_category_vii(source: Card) -> bool:
	return controls(source, {"is_type": "Forward", "is_category": "VII", "exclude": {"is_named": "Cloud"}})
