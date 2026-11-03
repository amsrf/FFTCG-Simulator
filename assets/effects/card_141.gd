extends "res://scripts/effects/card_effect.gd"
## 1-141L Lightning
##
## Entry: may search for Odin and add it to hand.
## Army of One 《S》《雷》: Haste, First Strike, and "when Lightning attacks, choose up to 1 Forward opponent
## controls. If it is possible, it must block Lightning this turn."


func trigger_specs() -> Array:
	return [
		trigger(EVENTS.Event.ENTER_FIELD, "when_enter_field"),
		trigger(EVENTS.Event.ATTACK, "when_attack"),
	]


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	if not await ctx.may("Search for Odin"):
		return
	await ctx.search_deck(CARD_QUERY.new().named("Odin"), "hand")


func when_attack(ctx: EFFECT_CONTEXT) -> void:
	# The attack trigger is printed by Army of One, so it only exists while that permission is on Lightning.
	if not ctx.source.status_effects.has("army_of_one"):
		return
	var targets: Array = await ctx.choose_targets(
		CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT), 1)
	if targets.is_empty():
		return
	ctx.add_status(targets, "must_block", 1, {
		"source_id": ctx.source.get_instance_id(),
		"source_name": ctx.source.card_name,
	})


func activated_abilities() -> Array:
	return [Ability0.new(self)]


class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Army of One 《S》《雷》: Until the end of the turn, Lightning gains Haste, First Strike and \"When Lightning attacks, choose up to 1 Forward opponent controls. If it is possible, it must block Lightning this turn\"."
		s_cost = true
		cost = {"雷": 1}
		tap = false

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		ctx.add_status([ctx.source], "haste", 1)
		ctx.add_status([ctx.source], "first_strike", 1)
		ctx.add_status([ctx.source], "army_of_one", 1)
