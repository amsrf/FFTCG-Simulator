extends RefCounted
## Maps a card id to its code effect. Kept separate from Card so the mapping is one searchable place and adding a card
## never means editing Card.gd.
##
## Effects are stateless; the instance is cached and shared by every copy of that card. A card with no
## assets/effects/card_<id>.gd keeps using the old data-driven JSON path.

const EFFECT_DIR := "res://assets/effects"

static var _instances: Dictionary = {}


static func for_card_id(card_id: int):
	if _instances.has(card_id):
		return _instances[card_id]
	var path: String = "%s/card_%d.gd" % [EFFECT_DIR, card_id]
	if not ResourceLoader.exists(path):
		return null
	var script = load(path)
	if script == null:
		return null
	var effect = script.new()
	_instances[card_id] = effect
	return effect


static func has_effect(card_id: int) -> bool:
	return ResourceLoader.exists("%s/card_%d.gd" % [EFFECT_DIR, card_id])
