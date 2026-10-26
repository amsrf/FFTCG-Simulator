extends "res://scripts/effects/card_effect.gd"
## 1-206 Biggs: when one of your Backups leaves the field, damage every opponent Forward.


func card_left_field(ctx) -> void:
	var left: Card = ctx.event_data.get("card")
	if left == null or not is_instance_valid(left):
		return
	if left.type != "Backup" or left.controller != ctx.controller:
		return
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 1000)
