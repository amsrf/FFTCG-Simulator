extends "res://scripts/effects/card_effect.gd"
## 1-096C Mystic


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _self_pump(ctx: EFFECT_CONTEXT) -> void:
	ctx.power_change([ctx.source], 3000, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Put 1 Backup into the Break Zone: Mystic gains +3000 power until the end of the turn."
		cost = {}
		sacrifice = {"is_type": "Backup", "controller": "player"}

	func on_resolve(ctx: EFFECT_CONTEXT) -> void:
		await _owner._self_pump(ctx)
