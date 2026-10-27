extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 7-054L Chelinka


func handlers() -> Dictionary:
	return {
		EVENTS.Event.PARTY_ATTACK: Callable(self, "when_party_attack"),
	}


func when_party_attack(ctx: EFFECT_CONTEXT) -> void:
	if not ctx.condition("party_has_named:Yuri"):
		return
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_any_type(["Forward", "Monster"])))
	if targets.is_empty():
		return
	ctx.break_cards(targets)
