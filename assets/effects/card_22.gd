extends "res://scripts/effects/card_effect.gd"
## 1-022R Firion

func activated_abilities() -> Array:
	return [Ability0.new(self), Ability1.new(self), Ability2.new(self), Ability3.new(self)]
func _first_strike(ctx) -> void:
	ctx.add_status([ctx.source], "first_strike", 1)

func _brave(ctx) -> void:
	ctx.add_status([ctx.source], "brave", 1)

func _ping(ctx) -> void:
	ctx.damage(ctx.targets, 1000)

func _pump(ctx) -> void:
	ctx.source.power_change(1000, 1)

class Ability0 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《1》: Firion gains First Strike until the end of the turn."
		cost = {"neutral": 1}

	func on_resolve(ctx) -> void:
		await _owner._first_strike(ctx)

class Ability1 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《1》: Firion gains Brave until the end of the turn."
		cost = {"neutral": 1}

	func on_resolve(ctx) -> void:
		await _owner._brave(ctx)

class Ability2 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《2》: Choose 1 Forward. Deal it 1000 damage."
		cost = {"neutral": 2}
		targets = {"is_type": "Forward"}

	func on_resolve(ctx) -> void:
		await _owner._ping(ctx)

class Ability3 extends "res://scripts/effects/card_ability.gd":
	func _init(owner = null) -> void:
		super(owner)
		text = "《2》: Firion gains +1000 power until the end of the turn."
		cost = {"neutral": 2}

	func on_resolve(ctx) -> void:
		await _owner._pump(ctx)
