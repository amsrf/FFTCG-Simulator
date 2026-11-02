extends "res://scripts/effects/card_effect.gd"
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## Cloud 1-187R: costs 1 less for each other Category VII Forward you control.


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.FORWARD_ATTACKS, "forward_attacks").card(
			CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR)),
	]


func modify_cost(ctx: COST_CONTEXT, _card: Card, cost: Dictionary) -> Dictionary:
	var count: int = ctx.cards_in_field(
		CARD_QUERY.new().of_category("VII").of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR), true).size()
	return ctx.adjust(cost, -count)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.damage(targets, 8000)

func forward_attacks(ctx: EFFECT_CONTEXT) -> void:
	var event_card: Card = ctx.event_card()
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
