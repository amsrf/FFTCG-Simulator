extends Node
## One-off: describe a PNG numerically.
##
## The image tool hangs on this project's large references, so this reads the pixels directly and
## prints structure a person can judge: an ASCII luminance map, the panel split, and the colours.

const PATH := "res://references/editor.png"
## ASCII cells. Coarse on purpose — this is for reading LAYOUT, not fine detail.
const CELLS_X := 96
const CELLS_Y := 40

func _ready() -> void:
	var img := Image.new()
	var err: int = img.load(PATH)
	if err != OK:
		print("[PngProbe] load failed: %d" % err)
		get_tree().quit()
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	print("[PngProbe] %s  %dx%d  aspect %.3f" % [PATH, w, h, float(w) / float(h)])

	_ascii_map(img, w, h)
	_panel_split(img, w, h)
	_palette(img, w, h)
	get_tree().quit()

## Average colour per cell, printed as a character. Legend:
##   '#' near-black   '+' dark      '-' mid      '.' light      ' ' near-white
##   'R' red-dominant 'G' green-    'B' blue-    'Y' yellow-    'O' orange
func _ascii_map(img: Image, w: int, h: int) -> void:
	print("[PngProbe] --- luminance map (%d x %d cells, one char per cell) ---" % [CELLS_X, CELLS_Y])
	var cw: int = int(ceil(float(w) / float(CELLS_X)))
	var ch: int = int(ceil(float(h) / float(CELLS_Y)))
	for cy in range(CELLS_Y):
		var line: String = ""
		for cx in range(CELLS_X):
			var r: float = 0.0
			var g: float = 0.0
			var b: float = 0.0
			var n: int = 0
			for y in range(cy * ch, mini((cy + 1) * ch, h), 3):
				for x in range(cx * cw, mini((cx + 1) * cw, w), 3):
					var c: Color = img.get_pixel(x, y)
					r += c.r; g += c.g; b += c.b
					n += 1
			if n == 0:
				line += " "
				continue
			r /= n; g /= n; b /= n
			line += _classify(r, g, b)
		print("|" + line + "|")
	print("[PngProbe] legend: # black  + dark  - mid  . light  (space) white  R red  G green  B blue  Y yellow  O orange")

func _classify(r: float, g: float, b: float) -> String:
	var maxc: float = maxf(r, maxf(g, b))
	var minc: float = minf(r, minf(g, b))
	var sat: float = 0.0 if maxc <= 0.001 else (maxc - minc) / maxc
	# Only call something "coloured" when it is clearly saturated; UI greys must not read as hues.
	if sat > 0.30 and maxc > 0.12:
		if r >= g and r >= b:
			return "O" if (g / maxf(r, 0.001)) > 0.5 else "R"
		if g >= r and g >= b:
			return "Y" if (r / maxf(g, 0.001)) > 0.7 else "G"
		return "B"
	if maxc < 0.10: return "#"
	if maxc < 0.25: return "+"
	if maxc < 0.55: return "-"
	if maxc < 0.85: return "."
	return " "

## Which columns are a single flat colour top to bottom? Those are panel backgrounds or gutters, and
## the runs tell us where the panels are without guessing.
func _panel_split(img: Image, w: int, h: int) -> void:
	print("[PngProbe] --- column profile (flat = same colour down the whole column) ---")
	var runs: Array = []
	var run_start: int = 0
	var prev_flat: bool = _column_is_flat(img, 0, h)
	for x in range(1, w):
		var flat: bool = _column_is_flat(img, x, h)
		if flat != prev_flat:
			runs.append({"start": run_start, "end": x - 1, "flat": prev_flat})
			run_start = x
			prev_flat = flat
	runs.append({"start": run_start, "end": w - 1, "flat": prev_flat})
	for r in runs:
		var width: int = int(r["end"]) - int(r["start"]) + 1
		if width < 8:
			continue
		var mid: int = (int(r["start"]) + int(r["end"])) / 2
		var c: Color = img.get_pixel(mid, h / 2)
		print("  x %4d..%4d  width %4d  %-7s  colour %s" % [
			r["start"], r["end"], width,
			"FLAT" if r["flat"] else "varied",
			"#%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]])

func _column_is_flat(img: Image, x: int, h: int) -> bool:
	var first: Color = img.get_pixel(x, 0)
	for y in range(0, h, 7):
		var c: Color = img.get_pixel(x, y)
		if absf(c.r - first.r) > 0.04 or absf(c.g - first.g) > 0.04 or absf(c.b - first.b) > 0.04:
			return false
	return true

## The handful of colours covering most of the image, and where each one sits.
func _palette(img: Image, w: int, h: int) -> void:
	print("[PngProbe] --- dominant colours (quantised 32-step buckets) ---")
	var counts: Dictionary = {}
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var c: Color = img.get_pixel(x, y)
			var key: String = "%d_%d_%d" % [int(c.r * 7.999), int(c.g * 7.999), int(c.b * 7.999)]
			if not counts.has(key):
				counts[key] = {"n": 0, "minx": x, "maxx": x, "miny": y, "maxy": y}
			var e: Dictionary = counts[key]
			e["n"] += 1
			e["minx"] = mini(e["minx"], x); e["maxx"] = maxi(e["maxx"], x)
			e["miny"] = mini(e["miny"], y); e["maxy"] = maxi(e["maxy"], y)
	var sorted_keys: Array = counts.keys()
	sorted_keys.sort_custom(func(a, b): return counts[a]["n"] > counts[b]["n"])
	for i in range(mini(10, sorted_keys.size())):
		var key: String = sorted_keys[i]
		var e: Dictionary = counts[key]
		var parts: PackedStringArray = key.split("_")
		var approx := Color(float(parts[0]) / 8.0, float(parts[1]) / 8.0, float(parts[2]) / 8.0)
		print("  #%02x%02x%02x  %5.1f%%  x %4d..%4d  y %4d..%4d" % [
			int(approx.r * 255), int(approx.g * 255), int(approx.b * 255),
			100.0 * float(e["n"]) / float((w / 4) * (h / 4)),
			e["minx"], e["maxx"], e["miny"], e["maxy"]])
