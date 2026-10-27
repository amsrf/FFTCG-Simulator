extends "res://scripts/effects/card_effect.gd"
## 1-094R Vincent
## Berserk Dance 《S》《Dull》: Choose 1 Forward. Deal it 6000 damage.


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _berserk_dance(ctx) -> void:
	ctx.damage(ctx.targets, 6000)

func when_attack(ctx) -> void:
	ctx.add_status([ctx.source], "first_strike", 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Berserk Dance 《S》《ダル》: Choose 1 Forward. Deal it 6000 damage."
		s_cost = true
		cost = {}
		tap = true
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._berserk_dance(ctx)
