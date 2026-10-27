extends RefCounted
## One typed targeting request: where to look, which cards match, and how many may be picked.
##
## This is the typed replacement for a criteria dictionary that also carries `count` and `in`. The engine still
## consumes the legacy block internally, so existing cards keep working while they are migrated.

const CARD_QUERY := preload("res://scripts/effects/card_query.gd")

enum Domain { FIELD, STACK, HAND, DECK, BREAK_ZONE, REVEALED }

var domain: Domain = Domain.FIELD
var query = null
var max_count: int = 1
var exact: bool = false


static func field(criteria = null):
	var request = load("res://scripts/effects/target_request.gd").new()
	request.domain = Domain.FIELD
	request.query = criteria
	return request


static func stack(criteria = null):
	var request = load("res://scripts/effects/target_request.gd").new()
	request.domain = Domain.STACK
	request.query = criteria
	return request


func up_to(count: int):
	max_count = maxi(1, count)
	exact = false
	return self


func exactly(count: int):
	max_count = maxi(1, count)
	exact = true
	return self


## The target block the current Field/Agent targeting session understands.
func to_legacy() -> Dictionary:
	var block: Dictionary = query.to_block() if query != null else {}
	if max_count > 1:
		block["count"] = max_count
	match domain:
		Domain.STACK:
			block["in"] = "stack"
		Domain.HAND:
			block["in"] = "hand"
		Domain.DECK:
			block["in"] = "deck"
		Domain.BREAK_ZONE:
			block["in"] = "break_zone"
		Domain.REVEALED:
			block["in"] = "revealed"
	return block
