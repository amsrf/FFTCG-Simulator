extends "res://scripts/effects/card_effect.gd"
## Tidus 1-213R: costs 1 less for each other Category X Forward you control.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.CARD_LEFT_FIELD, "card_left_field")
			.card(CARD_QUERY.new().named("Yuna").controlled_by(CARD_QUERY.Controller.YOUR))
			.to_zone(Card.Zone.GRAVEYARD),
	]


func modify_cost(ctx: COST_CONTEXT, _card: Card, cost: Dictionary) -> Dictionary:
	var count: int = ctx.cards_in_field(
		CARD_QUERY.new().of_category("X").of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR), true).size()
	return ctx.adjust(cost, -count)

func card_left_field(ctx: EFFECT_CONTEXT) -> void:
	ctx.draw(ctx.owner_id, 2)


func properties(ctx: EFFECT_CONTEXT) -> Array[String]:
	return ["brave"] if controls(ctx.source, CARD_QUERY.new().named("Yuna")) else []
