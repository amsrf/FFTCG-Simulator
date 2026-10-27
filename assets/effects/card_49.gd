extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
const TARGET_REQUEST := preload("res://scripts/effects/target_request.gd")
## 1-049C Time Mage
## 《Ice》《1》《Dull》: Choose 1 Forward. It cannot attack this turn.


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _stop_forward(ctx) -> void:
	ctx.add_status(ctx.targets, "cannot_attack", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《氷》《1》《Dull》: Choose 1 Forward. It cannot attack this turn."
		cost = {"氷": 1, "neutral": 1}
		tap = true
		targets = TARGET_REQUEST.field(CARD_QUERY.new().of_type("Forward"))

	func on_resolve(ctx) -> void:
		await _owner._stop_forward(ctx)
