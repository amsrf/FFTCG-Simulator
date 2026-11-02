extends "res://scripts/effects/card_effect.gd"
## 1-206 Biggs: when one of your Backups leaves the field, damage every opponent Forward.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.CARD_LEFT_FIELD, "card_left_field").card(
			CARD_QUERY.new().of_type("Backup").controlled_by(CARD_QUERY.Controller.YOUR)),
	]


func card_left_field(ctx: EFFECT_CONTEXT) -> void:
	ctx.damage(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)), 1000)
