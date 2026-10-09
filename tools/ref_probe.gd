extends Node
## One-off: describe a reference PNG numerically.
##
## Retargetable, because the image tool hangs on these files: pass the path as a user arg, e.g.
##   godot --headless res://tools/ref_probe.tscn -- res://references/editor2.png
## Prints an ASCII luminance map, the panel split, and the dominant colours.

const DEFAULT_PATH := "res://references/editor2.png"
const CELLS_X := 96
const CELLS_Y := 42

func _ready() -> void:
	var path: String = DEFAULT_PATH
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]
	var img := Image.new()
	if img.load(path) != OK:
		print("[RefProbe] cannot load %s" % path)
		get_tree().quit()
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	print("[RefProbe] %s  %dx%d  aspect %.3f" % [path, w, h, float(w) / float(h)])
	_ascii(img, w, h)
	_bands(img, w, h)
	_palette(img, w, h)
	get_tree().quit()

func _classify(c: Color) -> String:
	var hi: float = maxf(c.r, maxf(c.g, c.b))
	var lo: float = minf(c.r, minf(c.g, c.b))
	var sat: float = 0.0 if hi <= 0.001 else (hi - lo) / hi
	if sat > 0.30 and hi > 0.12:
		if c.r >= c.g and c.r >= c.b:
			return "O" if (c.g / maxf(c.r, 0.001)) > 0.5 else "R"
		if c.g >= c.r and c.g >= c.b:
			return "Y" if (c.r / maxf(c.g, 0.001)) > 0.7 else "G"
		return "B"
	if hi < 0.10: return "#"
	if hi < 0.25: return "+"
	if hi < 0.55: return "-"
	if hi < 0.85: return "."
	return " "

func _ascii(img: Image, w: int, h: int) -> void:
	print("[RefProbe] --- map (%d x %d cells) ---" % [CELLS_X, CELLS_Y])
	var cw: int = int(ceil(float(w) / float(CELLS_X)))
	var chh: int = int(ceil(float(h) / float(CELLS_Y)))
	for cy in range(CELLS_Y):
		var line: String = ""
		for cx in range(CELLS_X):
			var c: Color = img.get_pixel(mini(cx * cw + cw / 2, w - 1), mini(cy * chh + chh / 2, h - 1))
			line += _classify(c)
		print("|" + line + "|")
	print("[RefProbe] legend: # black + dark - mid . light (sp) white | R red G green B blue Y yellow O orange")

## Average luminance per horizontal band, to find where the card rows and the deck strip are.
func _bands(img: Image, w: int, h: int) -> void:
	print("[RefProbe] --- band profile (brightness of x 40..1400 per 8 px of height) ---")
	var line: String = ""
	for y in range(0, h, 8):
		var total: float = 0.0
		var n: int = 0
		for x in range(40, 1400, 10):
			var c: Color = img.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
			n += 1
		var avg: float = total / maxf(n, 1)
		line += " " if avg > 0.62 else ("." if avg > 0.38 else ("-" if avg > 0.16 else "#"))
	print("|" + line + "|")
	print("[RefProbe] one char per 8 px; '#'=dark, ' '=bright. Card rows read as runs of '.'")

func _palette(img: Image, w: int, h: int) -> void:
	print("[RefProbe] --- dominant colours ---")
	var counts: Dictionary = {}
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var c: Color = img.get_pixel(x, y)
			var key: String = "%d_%d_%d" % [int(c.r * 7.999), int(c.g * 7.999), int(c.b * 7.999)]
			if not counts.has(key):
				counts[key] = {"n": 0, "miny": y, "maxy": y}
			counts[key]["n"] += 1
			counts[key]["miny"] = mini(counts[key]["miny"], y)
			counts[key]["maxy"] = maxi(counts[key]["maxy"], y)
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return counts[a]["n"] > counts[b]["n"])
	for i in range(mini(8, keys.size())):
		var parts: PackedStringArray = str(keys[i]).split("_")
		var approx := Color(float(parts[0]) / 8.0, float(parts[1]) / 8.0, float(parts[2]) / 8.0)
		print("  #%02x%02x%02x  %5.1f%%  y %4d..%4d" % [
			int(approx.r * 255), int(approx.g * 255), int(approx.b * 255),
			100.0 * float(counts[keys[i]]["n"]) / float((w / 4) * (h / 4)),
			counts[keys[i]]["miny"], counts[keys[i]]["maxy"]])
