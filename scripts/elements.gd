extends RefCounted
## THE ELEMENT LOOKUP TABLE — spellings and colours, nothing else.
##
## Extracted from the old ElementBadge so the crystal row, the payment breakdown and the mana model can share it
## without dragging a 3D badge scene, a shader and a folder of baked PNGs along with them. Static-only: preload it
## and call `key_to_element`, `index_of`, or read `NAMES` / `CJK` / `ACCENT`.
##
## Callers preload this by PATH rather than naming a class, because a class_name added since Godot last scanned the
## project is not in the global cache during a headless run.

## The sheet's order, and the two spellings of each element: the ASCII name used for cost keys, and the CJK
## character the cards and the mana model use.
const NAMES: Array[String] = ["fire", "ice", "wind", "earth", "lightning", "water", "light", "dark"]
const CJK: Array[String] = ["火", "氷", "風", "土", "雷", "水", "光", "闇"]
## The accent ring per element, in the sheet's own colours.
const ACCENT: Array[Color] = [
	Color(1.00, 0.38, 0.18),   # fire
	Color(0.55, 0.87, 0.98),   # ice
	Color(0.36, 0.85, 0.44),   # wind
	Color(0.90, 0.74, 0.26),   # earth
	Color(0.72, 0.45, 1.00),   # lightning
	Color(0.32, 0.58, 1.00),   # water
	Color(1.00, 0.95, 0.78),   # light
	Color(0.58, 0.52, 0.86),   # dark
]

## Cost Dictionaries key elements either by String ("fire", "neutral") or by a one-element Array (["火"]) — the
## latter because that is how `card.element` is stored. Both have to reach the same table, so every key goes
## through here first.
static func key_to_element(key: Variant) -> String:
	if key is Array:
		var a: Array = key
		return str(a[0]) if a.size() > 0 else ""
	return str(key)

## Index of `key` in NAMES, or -1 if it is neither an ASCII name nor a CJK key.
static func index_of(key: Variant) -> int:
	var text: String = key_to_element(key).strip_edges()
	var i: int = NAMES.find(text.to_lower())
	if i >= 0:
		return i
	return CJK.find(text)
