extends "res://scripts/effects/card_effect.gd"
## Tidus 1-213R: costs 1 less for each other Category X Forward you control.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.CARD_LEFT_FIELD: Callable(self, "card_left_field"),
	}


func modify_cost(ctx, _card: Card, cost: Dictionary) -> Dictionary:
	var count: int = ctx.cards_in_field(
		{"is_category": "X", "is_type": "Forward", "controller": "your"}, true).size()
	return ctx.adjust(cost, -count)

func event_matches(event: int, source: Card, data: Dictionary) -> bool:
	if event != EVENTS.Event.CARD_LEFT_FIELD:
		return false
	var event_card: Card = data.get("card")
	return event_card != null and is_instance_valid(event_card) \
		and event_card.card_name == "Yuna" and event_card.controller == source.controller


func card_left_field(ctx) -> void:
	ctx.draw(ctx.owner_id, 2)


func static_rules() -> Dictionary:
	return {"conditional_status": [{"status": "brave", "if_controls": {"is_named": "Yuna"}}]}
