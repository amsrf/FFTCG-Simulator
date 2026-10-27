extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-082R Hope


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	if ctx.condition("cast_this_turn:Alexander"):
		ctx.untap_all_matching(CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.PLAYER))
		return
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.PLAYER)))
	ctx.untap(targets)
