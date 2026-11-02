extends "res://scripts/effects/card_effect.gd"
## 1-095C


func auras() -> Array:

	return [Aura0.new()]

class Aura0 extends "res://scripts/effects/aura.gd":
	func _init() -> void:
		query = CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.PLAYER).of_element("土")
		kind = KIND_POWER
		value = 1000
