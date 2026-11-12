extends "res://scripts/effects/card_effect.gd"
## 1-198S Valefor


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.CAST, "when_cast"),
	]


func when_cast(ctx: EFFECT_CONTEXT) -> void:
	var forwards: Array = ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT))
	ctx.damage(forwards, 3000)
	if ctx.condition("controls:Yuna"):
		ctx.untap_all_matching(CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.PLAYER))


func ex_burst_event() -> int:
	return EVENTS.Event.CAST
