extends Node
## Measures the hand reference's fan out of its own pixels.
##
## The image tool is unreliable on this file and eyeballing it has cost several rounds of guess-and-check. A fanned hand
## is a row of strong VERTICAL edges, one per card boundary — but a screenshot's texture is full of weak ones, so a
## column's score is HOW MANY ROWS it stays an edge for, not how big its total gradient is. Card borders are long; noise
## is short. The spacing between the surviving columns IS the step, reported as a FRACTION OF A CARD'S WIDTH, which is
## the number Hand.FAN_STEP_FRACTION holds.

const IMAGE := "res://references/hand.png"
## A pixel counts as an edge when it steps this far in luminance.
const EDGE_STEP := 0.10
## What fraction of the band's rows a column must be an edge for, to count as a card border.
const EDGE_RUN := 0.45
## The bottom slice of the image, which is where the fan is.
const BAND_TOP := 0.55

func _ready() -> void:
	var img: Image = Image.load_from_file(IMAGE)
	if img == null:
		push_error("[HandMeasure] could not load %s" % IMAGE)
		get_tree().quit()
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	var y0: int = int(h * BAND_TOP)
	var rows: int = h - y0
	print("[HandMeasure] %dx%d, scoring columns over y %d..%d (%d rows)" % [w, h, y0, h, rows])

	var profile: PackedFloat32Array = PackedFloat32Array()
	profile.resize(w)
	for x in range(1, w):
		var hit: int = 0
		for y in range(y0, h):
			if absf(img.get_pixel(x, y).get_luminance() - img.get_pixel(x - 1, y).get_luminance()) > EDGE_STEP:
				hit += 1
		profile[x] = float(hit)

	# The profile as a chart, so the peaks can be READ OFF rather than trusted.
	var levels: int = 12
	var grid: Array[String] = []
	for _r in range(levels):
		grid.append("")
	for x in range(w):
		var level: int = clampi(int(profile[x] / float(rows) * levels), 0, levels)
		for r in range(levels):
			grid[r] += ("#" if (levels - r) <= level else " ")
	for r in range(levels):
		print("  %s" % grid[r])

	# Columns that stay an edge for most of the band — the card borders.
	var borders: Array[int] = []
	for x in range(1, w):
		if profile[x] < rows * EDGE_RUN:
			continue
		if borders.is_empty() or x - borders[borders.size() - 1] > 3:
			borders.append(x)
		elif profile[x] > profile[borders[borders.size() - 1]]:
			borders[borders.size() - 1] = x
	var gaps: Array[float] = []
	for i in range(1, borders.size()):
		gaps.append(float(borders[i] - borders[i - 1]))
	var sorted_gaps: Array[float] = gaps.duplicate()
	sorted_gaps.sort()
	print("[HandMeasure] %d long edges at x = %s" % [borders.size(), str(borders)])
	print("[HandMeasure] gaps: %s" % str(sorted_gaps))
	if sorted_gaps.is_empty():
		print("[HandMeasure] no card borders survived — raise EDGE_RUN or widen the band")
		get_tree().quit()
		return
	var median: float = sorted_gaps[sorted_gaps.size() / 2]
	print("[HandMeasure] median gap between borders = %.1f px" % median)
	for card_w in [100.0, 110.0, 120.0, 130.0, 140.0, 150.0]:
		print("[HandMeasure]   if a card is %.0f px wide -> step fraction %.3f" % [card_w, median / card_w])
	get_tree().quit()
