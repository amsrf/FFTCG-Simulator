extends "res://scripts/effects/card_effect.gd"
const CARD_QUERY := preload("res://scripts/effects/card_query.gd")
## 1-156C


func auras() -> Array:

	return [Aura0.new()]

class Aura0 extends "res://scripts/effects/aura.gd":
	func _init() -> void:
		query = CARD_QUERY.new().of_type("Forward").controlled_by(CARD_QUERY.Controller.PLAYER).with_job("Knight")
		kind = KIND_POWER
		value = 1000
