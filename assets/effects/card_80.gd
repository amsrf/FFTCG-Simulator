extends "res://scripts/effects/card_effect.gd"
## 1-080 enter-the-field ability


func when_enter_field(ctx) -> void:
	ctx.untap_all_matching({"is_character": true, "controller": "your", "is_element": "風"})
