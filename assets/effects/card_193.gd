extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-193S Jihl Nabaat


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward")).up_to(2))
	ctx.add_status(targets, "frozen", 1)


func ex_burst_event() -> int:
	return EVENTS.Event.ENTER_FIELD


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.dull(targets)
	ctx.add_status(targets, "frozen", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Sadistic Surge 《S》《Ice》《Dull》: Choose 1 Forward. Dull it and Freeze it."
		cost = {"氷": 1}
		tap = true
		s_cost = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))
		target_count = 1

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._skill_0(ctx)
