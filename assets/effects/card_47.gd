extends "res://scripts/effects/card_effect.gd"
## 1-047R Terra
## 《Ice》: Choose 1 dull Forward. Deal it 1000 damage.


func activated_abilities() -> Array:
	return [Ability0.new(self)]
func _ice_shot(ctx) -> void:
	ctx.damage(ctx.targets, 1000)

func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({
		"is_type": "Forward", "controller": "opponent", "is_tapped": true,
	}, 2)
	ctx.damage(targets, 4000)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《氷》: Choose 1 dull Forward. Deal it 1000 damage."
		cost = {"氷": 1}
		tap = false
		targets = {"is_type": "Forward", "is_tapped": true}

	func on_resolve(ctx) -> void:
		await _owner._ice_shot(ctx)
