extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-047R Terra
## 《Ice》: Choose 1 dull Forward. Deal it 1000 damage.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field"),
	}


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _ice_shot(ctx: EFFECT_CONTEXT) -> void:
	ctx.damage(ctx.targets, 1000)

func when_enter_field(ctx: EFFECT_CONTEXT) -> void:
	var targets: Array = await ctx.choose_targets(TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.OPPONENT).tapped(true)).up_to(2))
	ctx.damage(targets, 4000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《氷》: Choose 1 dull Forward. Deal it 1000 damage."
		cost = {"氷": 1}
		tap = false
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").tapped(true))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._ice_shot(ctx)
