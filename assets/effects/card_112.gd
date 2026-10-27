extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-112R Delita


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().character(true).controlled_by(CARD_QUERY.Controller.PLAYER)))
	if targets.is_empty():
		return
	ctx.break_cards(targets)


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	if not targets.is_empty():
		ctx.break_cards(targets)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Northswain's Strike 《S》《Earth》: Choose 1 Forward blocking Delita. Break it."
		cost = {"土": 1}
		s_cost = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").blocking(true))
		target_count = 1

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)
