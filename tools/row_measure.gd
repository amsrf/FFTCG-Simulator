extends Node
## Measures a card-row reference PNG numerically: where the panels are, how many cards there are, how far
## apart they sit, how much they overlap, which way they lean and whether the row arcs.
##
## Written because the image tool is unavailable: it fails on every input in this session, from a 17 KB file to a
## 2.5 MB one, so "look at the reference" has to mean "measure the reference" or not happen at all.
##
##   godot --headless res://tools/row_measure.tscn -- res://references/search.png

const DEFAULT_PATH := "res://references/search.png"
## Columns in the width profile. One per ~10 px of a 1694 px image, which is fine enough to separate cards.
const PROFILE_COLS := 170

func _ready() -> void:
	var path: String = DEFAULT_PATH
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]

	var img := Image.new()
	if img.load(path) != OK:
		print("[RowMeasure] cannot load %s" % path)
		get_tree().quit(1)
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	print("[RowMeasure] %s  %dx%d" % [path, w, h])

	_panels(img, w, h)
	var band: Vector2i = _card_band(img, w, h)
	print("[RowMeasure] card band y %d..%d" % [band.x, band.y])
	_profile(img, w, band)
	get_tree().quit()

## Where the horizontal panels are: for each row, the dominant colour. A change of dominant colour is a seam.
func _panels(img: Image, w: int, h: int) -> void:
	print("[RowMeasure] --- panels (dominant colour per row, sampled every 4 px of height) ---")
	var last: String = ""
	var run_start: int = 0
	for y in range(0, h, 4):
		var counts: Dictionary = {}
		for x in range(0, w, 12):
			var c: Color = img.get_pixel(x, y)
			var key: String = _bucket(c)
			counts[key] = counts.get(key, 0) + 1
		var best: String = ""
		var best_n: int = -1
		for k in counts:
			if counts[k] > best_n:
				best_n = counts[k]
				best = k
		if best != last:
			if last != "":
				print("  y %4d..%4d  %5.1f%%..%5.1f%%  %s" % [
					run_start, y - 1, 100.0 * run_start / h, 100.0 * (y - 1) / h, last])
			last = best
			run_start = y
	print("  y %4d..%4d  %5.1f%%..%5.1f%%  %s" % [run_start, h - 1,
		100.0 * run_start / h, 100.0, last])

func _bucket(c: Color) -> String:
	return "#%02x%02x%02x" % [int(c.r * 15.0) * 17, int(c.g * 15.0) * 17, int(c.b * 15.0) * 17]

## The band the cards live in: the rows with the MOST colour, since card art is far more colourful than panels.
func _card_band(img: Image, w: int, h: int) -> Vector2i:
	var rows: Array = []
	for y in range(h):
		var colourful: int = 0
		for x in range(0, w, 6):
			var c: Color = img.get_pixel(x, y)
			var hi: float = maxf(c.r, maxf(c.g, c.b))
			var lo: float = minf(c.r, minf(c.g, c.b))
			if hi > 0.20 and (hi - lo) / maxf(hi, 0.001) > 0.30:
				colourful += 1
		rows.append(colourful)
	# The band is the longest run of rows above half the peak colourfulness.
	var peak: int = 0
	for v in rows:
		peak = maxi(peak, int(v))
	var threshold: int = peak / 2
	var best_start: int = 0
	var best_len: int = 0
	var start: int = -1
	for y in range(h):
		if int(rows[y]) >= threshold:
			if start < 0:
				start = y
		else:
			if start >= 0 and y - start > best_len:
				best_len = y - start
				best_start = start
			start = -1
	if start >= 0 and h - start > best_len:
		best_len = h - start
		best_start = start
	return Vector2i(best_start, best_start + best_len - 1)

## A per-column count of "not background" pixels across the card band. Card bodies read as tall runs; the gaps
## between them, if any, read as low ones; and a visible card EDGE reads as a spike even where cards overlap.
func _profile(img: Image, w: int, band: Vector2i) -> void:
	print("[RowMeasure] --- column profile across the band (one char per column) ---")
	var cw: int = maxi(1, w / PROFILE_COLS)
	var values: Array = []
	for cx in range(PROFILE_COLS):
		var x: int = mini(cx * cw + cw / 2, w - 1)
		var count: int = 0
		var bright: int = 0
		for y in range(band.x, band.y + 1, 2):
			var c: Color = img.get_pixel(x, y)
			var hi: float = maxf(c.r, maxf(c.g, c.b))
			var lo: float = minf(c.r, minf(c.g, c.b))
			if hi > 0.20 and (hi - lo) / maxf(hi, 0.001) > 0.28:
				count += 1
			if (c.r + c.g + c.b) / 3.0 > 0.60:
				bright += 1
		values.append(count)
	# Two rows of output: colourfulness, then brightness. Read together they show where each card starts.
	var line_a: String = ""
	var line_b: String = ""
	for i in range(values.size()):
		line_a += " " if int(values[i]) > (band.y - band.x) / 6 else "."
		var x: int = mini(i * cw + cw / 2, w - 1)
		var bright: int = 0
		for y in range(band.x, band.y + 1, 2):
			var c: Color = img.get_pixel(x, y)
			if (c.r + c.g + c.b) / 3.0 > 0.60:
				bright += 1
		line_b += "#" if bright > (band.y - band.x) / 8 else " "
	print("  colourful |" + line_a + "|")
	print("  bright    |" + line_b + "|")
	print("  width %d px over %d columns, %.1f px per column" % [w, PROFILE_COLS, float(w) / PROFILE_COLS])
