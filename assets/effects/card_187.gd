extends "res://scripts/effects/card_effect.gd"
## Cloud 1-187R: costs 1 less for each other Category VII Forward you control.


func modify_cost(ctx, _card: Card, cost: Dictionary) -> Dictionary:
	var count: int = ctx.cards_in_field(
		{"is_category": "VII", "is_type": "Forward", "controller": "your"}, true).size()
	return ctx.adjust(cost, -count)


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Climhazzard 《S》《Fire》《1》《Dull》: Choose 1 Forward. Deal it 8000 damage.",
			"cost": {"火": 1, "neutral": 1},
			"tap": true,
			"s_cost": true,
			"targets": {"is_type": "Forward"},
			"target_count": 1,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.damage(targets, 8000)

func event_matches(event: String, source: Card, data: Dictionary) -> bool:
	if event != "forward_attacks":
		return false
	var event_card: Card = data.get("card")
	return event_card != null and is_instance_valid(event_card) \
		and event_card.is_type("Forward") and event_card.controller == source.controller


func forward_attacks(ctx) -> void:
	var event_card: Card = ctx.event_data.get("card")
	if event_card != null and is_instance_valid(event_card):
		ctx.power_change([event_card], 1000, 1)
