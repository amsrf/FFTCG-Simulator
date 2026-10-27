extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-146C Ricard


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _unbreakable_target(ctx: EFFECT_CONTEXT) -> void:
	ctx.add_status(ctx.targets, "unbreakable", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Lightning》, put Ricard into the Break Zone: Choose 1 Forward. It cannot be broken this turn."
		cost = {"雷": 1}
		sacrifice = {"is_source": true}
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._unbreakable_target(ctx)
