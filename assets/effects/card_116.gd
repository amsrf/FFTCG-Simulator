extends "res://scripts/effects/card_effect.gd"
## 1-116 Prishe: when this card blocks, it gains +4000.


func handlers() -> Dictionary:
	return {
		EVENTS.Event.BLOCKS: Callable(self, "when_blocks"),
	}


func when_blocks(ctx) -> void:
	ctx.power_change([ctx.source], 4000, 1)


func activated_abilities() -> Array:
	return [Ability0.new(self), Ability1.new(self)]
func _skill_0(ctx) -> void:
	ctx.add_status([ctx.source], "brave", 1)

func _skill_1(ctx) -> void:
	ctx.power_change([ctx.source], ctx.source.power, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《Earth》: Prishe gains Brave until the end of the turn."
		cost = {"土": 1}

	func on_resolve(ctx) -> void:
		await _owner._skill_0(ctx)

class Ability1 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "Auroral Uppercut 《S》《Earth》: Double the power of Prishe until the end of the turn."
		cost = {"土": 1}
		s_cost = true

	func on_resolve(ctx) -> void:
		await _owner._skill_1(ctx)
