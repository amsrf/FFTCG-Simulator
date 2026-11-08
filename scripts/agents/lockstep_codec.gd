extends RefCounted
## Turns agent decisions into plain JSON-safe data and back, for online lockstep play. Cards travel as {"uid": n}
## (Card.uid is identical on both machines); everything else is already plain data. Decoding needs the receiving
## game, to look the cards up again.
##
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the global cache.

static func encode(value: Variant) -> Variant:
	if value is Card:
		return {"uid": (value as Card).uid} if is_instance_valid(value) else null
	if value is Object:
		return null
	if value is Array:
		return (value as Array).map(func(v): return encode(v))
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value:
			out[str(key)] = encode(value[key])
		return out
	return value

static func decode(value: Variant, game: Node) -> Variant:
	if value is Dictionary:
		if value.size() == 1 and value.has("uid"):
			return game.card_by_uid(int(value["uid"]))
		var out: Dictionary = {}
		for key in value:
			out[key] = decode(value[key], game)
		return out
	if value is Array:
		return (value as Array).map(func(v): return decode(v, game))
	# JSON has one number type: whole numbers come back as floats.
	if value is float and value == floorf(value):
		return int(value)
	return value

static func to_wire(message: Dictionary) -> String:
	return JSON.stringify(encode(message))

static func from_wire(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
