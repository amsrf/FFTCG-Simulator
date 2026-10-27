extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-198S Valefor


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CAST: Callable(self, "when_cast"),
	}


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	var forwards: Array = ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT))
	ctx.damage(forwards, 3000)
	if ctx.condition("controls:Yuna"):
		ctx.untap_all_matching(CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.PLAYER))


func ex_burst_event() -> int:
	return EVENTS.Event.CAST
