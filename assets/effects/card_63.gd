extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-063 enter-the-field ability


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
		EVENTS.Event.ATTACK: Callable(self, "when_attack"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	if await ctx.may("Play a Forward"):
		await ctx.play_from_hand(CARD_QUERY.new().of_type("Forward").of_element("風").where({"is_cost_lower_than": 4}))

func when_attack(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.PLAYER)).up_to(2))
	ctx.untap(targets)
