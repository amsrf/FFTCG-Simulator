extends RefCounted
## The typed payload for one game event. Trigger filters read this instead of
## poking at a raw Dictionary, and the same object is flattened into the stack
## copy so the handler can read the event after it resolves.
const EVENTS := preload("res://scripts/effects/events.gd")

var event: int = EVENTS.Event.NONE
var card: Card = null
var from_zone: int = Card.Zone.NONE
var to_zone: int = Card.Zone.NONE
var cause: String = ""
var player_id: int = 0
var data: Dictionary = {}


func to_data() -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	out["event"] = event
	out["card"] = card
	out["from_zone"] = from_zone
	out["to_zone"] = to_zone
	out["cause"] = cause
	out["player_id"] = player_id
	return out
