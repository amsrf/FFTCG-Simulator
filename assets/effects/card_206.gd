extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-206 Biggs: when one of your Backups leaves the field, damage every opponent Forward.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CARD_LEFT_FIELD: Callable(self, "card_left_field"),
	}


func card_left_field(ctx: EFFECT_CONTEXT) -> void:
	var left: Card = ctx.event_data.get("card")
	if left == null or not is_instance_valid(left):
		return
	if left.type != "Backup" or left.controller != ctx.controller:
		return
	ctx.damage(ctx.cards_in("field", CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT)), 1000)
