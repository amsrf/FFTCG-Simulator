extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-104R Kefka


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _kefka_pump(ctx) -> void:
	ctx.power_change(ctx.targets, 5000, 1)
	ctx.add_status(ctx.targets, "break_at_end_of_turn", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Dull》: Choose 1 Forward you control. It gains +5000 power. At the end of the turn, break it."
		cost = {}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.YOUR))

	func on_resolve(ctx) -> void:
		await _owner._kefka_pump(ctx)
