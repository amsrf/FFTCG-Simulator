extends RefCounted
## Maps a card id to its code effect. Kept separate from Card so the mapping is one searchable place and adding a card
## never means editing Card.gd.
##
## Effects are stateless; the instance is cached and shared by every copy of that card. A card with no entry here keeps
## using the old data-driven JSON path.

const EFFECTS := {
	103: preload("res://assets/effects/card_103.gd"),
	107: preload("res://assets/effects/card_107.gd"),
}

static var _instances: Dictionary = {}


static func for_card_id(card_id: int):
	if _instances.has(card_id):
		return _instances[card_id]
	if not EFFECTS.has(card_id):
		return null
	var effect = EFFECTS[card_id].new()
	_instances[card_id] = effect
	return effect


static func has_effect(card_id: int) -> bool:
	return EFFECTS.has(card_id)
