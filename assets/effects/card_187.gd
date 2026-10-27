extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## Cloud 1-187R: costs 1 less for each other Category VII Forward you control.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.FORWARD_ATTACKS: Callable(self, "forward_attacks"),
	}


func modify_cost(ctx: COST_CONTEXT, _card: Card, cost: Dictionary) -> Dictionary:
	var count: int = ctx.cards_in_field(
		{"is_category": "VII", "is_type": "Forward", "controller": "your"}, true).size()
	return ctx.adjust(cost, -count)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.damage(targets, 8000)

func event_matches(event: int, source: Card, data: Dictionary) -> bool:
	if event != EVENTS.Event.FORWARD_ATTACKS:
		return false
	var event_card: Card = data.get("card")
	return event_card != null and is_instance_valid(event_card) \
		and event_card.is_type("Forward") and event_card.controller == source.controller


func forward_attacks(ctx: EFFECT_CONTEXT) -> void:
	var event_card: Card = ctx.event_data.get("card")
	if event_card != null and is_instance_valid(event_card):
		ctx.power_change([event_card], 1000, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Climhazzard 《S》《Fire》《1》《Dull》: Choose 1 Forward. Deal it 8000 damage."
		cost = {"火": 1, "neutral": 1}
		tap = true
		s_cost = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))
		target_count = 1

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)
