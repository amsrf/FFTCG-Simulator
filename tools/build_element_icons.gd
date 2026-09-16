extends Node
## Cuts the eight element icons out of references/icons.png into assets/elements/<element>.png.
##
## THAT SHEET IS RGBA, so the icons are CUT OUT rather than keyed. Nothing has to be removed from a
## background, and the artwork is used exactly as drawn — the previous source was a JPG of the glyphs on
## solid white, which had to be chroma-keyed and left a pale halo around every edge. That keying code is
## gone, along with the erode pass it needed.
##
## THE GRID IS DETECTED, NOT ASSUMED: runs of fully transparent columns and rows ARE the gaps between
## icons, so the sheet can be relaid out (2x4, 4x2, whatever) without touching this file. The detected
## layout, each icon's bounds, its alpha coverage and its mean colour are printed — which is how the
## arrangement gets confirmed without being able to look at the image: an orange first icon means fire
## came first, a cyan second means ice, and so on.
##
## NO RESCALING. The icons are ~26 px across, which is roughly the size they are displayed at, so crops
## are written at native pixel size and stay crisp. Trimming and re-centring only moves them.
##
## Run: godot --headless res://tools/build_element_icons.tscn
## Output: assets/elements/<element>.png (all the same square size) + _contact_sheet.png on magenta.

const SHEET := "res://references/icons.png"
const OUT_DIR := "res://assets/elements"
const CONTACT := "res://assets/elements/_contact_sheet.png"

## Reading order: left to right, then top to bottom. These names are the ones the cost model uses, so the
## icon for an element is found by the same name its cost is written with. CJK is how the cards spell it
## (card.element is ["火"]), which is what the badge is switched on.
const ELEMENTS: Array[String] = ["fire", "ice", "wind", "earth", "lightning", "water", "light", "dark"]
const CJK: Array[String] = ["火", "氷", "風", "土", "雷", "水", "光", "闇"]

const PAD_RATIO := 0.12      # of the trimmed glyph, so an icon never touches the texture edge
const ALPHA_FLOOR := 0.04    # below this a pixel counts as empty
const MAX_SIDE := 128        # safety cap, in case a sheet ever arrives much larger

func _ready() -> void:
	var sheet: Image = Image.load_from_file(SHEET)
	if sheet == null:
		push_error("[ElementIcons] could not load " + SHEET)
		get_tree().quit(1)
		return
	sheet.convert(Image.FORMAT_RGBA8)
	print("[ElementIcons] sheet %dx%d" % [sheet.get_width(), sheet.get_height()])
	_check_background(sheet)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# Bands are (start, length) pairs: a band is a run of columns (or rows) that contains any ink.
	var cols: Array[Vector2i] = _bands(sheet, true)
	var rows: Array[Vector2i] = _bands(sheet, false)
	print("[ElementIcons] detected %d column band(s) x %d row band(s) = %d cells"
		% [cols.size(), rows.size(), cols.size() * rows.size()])
	for c in cols:
		print("[ElementIcons]   column starts at x=%d, width %d" % [c.x, c.y])
	for r in rows:
		print("[ElementIcons]   row    starts at y=%d, height %d" % [r.x, r.y])

	# Trim every cell to its ink first, so the shared output size can be the largest of them — which keeps
	# the icons' relative sizes as the artist drew them instead of normalising each one.
	var trimmed: Array[Image] = []
	for r in rows:
		for c in cols:
			var cell: Image = sheet.get_region(Rect2i(c.x, r.x, c.y, r.y))
			var box: Rect2i = _ink_box(cell)
			trimmed.append(cell.get_region(box) if box.size.x > 0 else cell)
	print("[ElementIcons] %d cell(s) have ink" % trimmed.size())
	if trimmed.size() != ELEMENTS.size():
		push_warning("[ElementIcons] the sheet has %d icons but %d element names are declared — the extra "
			% [trimmed.size(), ELEMENTS.size()] + "cells are ignored and the missing ones keep their old files.")

	# Every cell gets a fingerprint, because the ELEMENTS order above is a guess from the PREVIOUS sheet and
	# this one is not laid out the same way: a 5x5 grid of 25 at a uniform 26 px pitch, most of which are
	# plainly not elements. Hue is what identifies an element — fire orange, ice cyan, wind green, earth
	# yellow, lightning purple, water blue, light pale, dark grey — so every cell's hue is printed and the
	# eight to use can be read off the numbers instead of guessed from an image.
	print("[ElementIcons] --- every cell: index, size, coverage, mean RGB, hue/sat/val ---")
	for i in trimmed.size():
		var t: Image = trimmed[i]
		var mean: Color = _mean_colour(t)
		print("[ElementIcons] cell %2d  %2dx%-2d  opaque %3.0f%%  rgb (%.2f, %.2f, %.2f)  hue %4.0f  sat %.2f  val %.2f"
			% [i, t.get_width(), t.get_height(), _coverage(t) * 100.0,
			   mean.r, mean.g, mean.b, mean.h * 360.0, mean.s, mean.v])

	# And the whole sheet as ASCII, so it can actually be READ here — the image tool cannot open this file,
	# and inventing a mapping from the numbers alone would be guessing. One character per 2x2 px, chosen
	# from that pixel's own colour, which makes both the SHAPE and the COLOUR of every icon visible.
	#   R red/orange-red  O orange  Y yellow  G green  C cyan  B blue  P purple  M magenta
	#   W white           g grey    k dark    . transparent
	print("[ElementIcons] --- the sheet (one char per 2x2 px): R O Y G C B P M / W g k . ---")
	var step: int = 2
	for ri in rows.size():
		var band: Vector2i = rows[ri]
		print("[ElementIcons] --- row %d ---" % ri)
		var line: int = 0
		while line < band.y:
			var text: String = "   "
			for ci in cols.size():
				var cb: Vector2i = cols[ci]
				var col: int = 0
				while col < cb.y:
					var c: Color = sheet.get_pixel(cb.x + col, band.x + line)
					var ch: String = "."
					if c.a >= 0.15:
						var h: float = c.h * 360.0
						if c.s < 0.18:
							ch = "W"
							if c.v <= 0.85: ch = "g"
							if c.v <= 0.50: ch = "k"
						elif h < 25.0 or h >= 335.0: ch = "R"
						elif h < 45.0: ch = "O"
						elif h < 75.0: ch = "Y"
						elif h < 175.0: ch = "G"
						elif h < 205.0: ch = "C"
						elif h < 250.0: ch = "B"
						elif h < 300.0: ch = "P"
						else: ch = "M"
					text += ch
					col += step
				text += "  "
			print("[ElementIcons] " + text)
			line += step

	var side: int = 1
	for t in trimmed:
		side = maxi(side, maxi(t.get_width(), t.get_height()))
	side = clampi(int(side * (1.0 + PAD_RATIO * 2.0)), 1, MAX_SIDE)

	# Centre every cell on the same square canvas. Done for ALL cells, which gives the contact sheet
	# something to show and means the element files are written from exactly the same pixels.
	var canvases: Array[Image] = []
	for t in trimmed:
		var canvas: Image = Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0.0, 0.0, 0.0, 0.0))
		canvas.blend_rect(t, Rect2i(0, 0, t.get_width(), t.get_height()),
			Vector2i((side - t.get_width()) / 2, (side - t.get_height()) / 2))
		canvases.append(canvas)

	# WHICH CELL HOLDS WHICH ELEMENT, as cell index -> element name, READ OFF THE ASCII DUMP ABOVE.
	#
	# This sheet is a SHADED ICON SET, not a row of eight: most glyphs appear several times over — in grey
	# and in white as well as their element colour — which is why the 5x5 grid made no sense read as eight
	# icons. The COLOURED copy of each glyph is the one wanted:
	#
	#   cell  3  yellow slab                        -> earth
	#   cell  7  orange-red flame                   -> fire
	#   cell 11  cyan snowflake   (grey 12, white 13 are copies of the same glyph)
	#   cell 14  blue droplet                       -> water
	#   cell 18  purple bolt                        -> lightning
	#   cell 21  green swirl      (grey 22, white 23 are copies)
	#   cell 15  white ring with radiating spokes   -> light
	#   cell  0  grey slab with a notch             -> dark
	#
	# fire, ice, wind, earth, lightning and water are certain — their colour and shape match the elements.
	# LIGHT and DARK are inferred: they have no element colour of their own, so the white and grey glyphs are
	# the only candidates, and which of the several white/grey copies is meant is a judgement call. If they
	# come out swapped, swap the two numbers here and re-run; nothing else has to change.
	var cell_of_element: Dictionary = {
		"fire": 7, "ice": 11, "wind": 21, "earth": 3,
		"lightning": 18, "water": 14, "light": 15, "dark": 0,
	}
	if cell_of_element.is_empty():
		push_warning("[ElementIcons] no cell_of_element mapping set, so no element icons were written. "
			+ "Read the fingerprints above, fill in the map, and re-run.")
	else:
		for element in cell_of_element:
			var idx: int = int(cell_of_element[element])
			if idx < 0 or idx >= canvases.size():
				push_warning("[ElementIcons] %s points at cell %d, which the sheet does not have"
					% [element, idx])
				continue
			canvases[idx].save_png("%s/%s.png" % [OUT_DIR, element])
			print("[ElementIcons] wrote %s.png from cell %d" % [element, idx])

	_write_contact(canvases, side)
	print("[ElementIcons] done")
	get_tree().quit()

## The sheet must be RGBA with a transparent background for any of this to be a plain cut-out. Say so
## loudly if it is not, because an opaque sheet would silently produce icons with square backgrounds.
func _check_background(sheet: Image) -> void:
	var probes: Array[Vector2i] = [Vector2i(0, 0), Vector2i(sheet.get_width() - 1, 0),
		Vector2i(0, sheet.get_height() - 1), Vector2i(sheet.get_width() - 1, sheet.get_height() - 1)]
	var opaque: int = 0
	for p in probes:
		if sheet.get_pixel(p.x, p.y).a > 0.5:
			opaque += 1
	if opaque > 0:
		push_warning("[ElementIcons] %d of the 4 corner pixels are opaque — this sheet is NOT a cut-out, "
			% opaque + "so the icons will come out with square backgrounds. It needs alpha, or the old "
			+ "white-keying approach has to come back.")
	else:
		print("[ElementIcons] corners are transparent — treating the sheet as a cut-out")

## Runs of columns (or rows) that contain any ink, as (start, length) pairs.
func _bands(img: Image, along_x: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var span: int = img.get_width() if along_x else img.get_height()
	var across: int = img.get_height() if along_x else img.get_width()
	var start: int = -1
	for i in span:
		var has_ink: bool = false
		for j in across:
			var c: Color = img.get_pixel(i, j) if along_x else img.get_pixel(j, i)
			if c.a > ALPHA_FLOOR:
				has_ink = true
				break
		if has_ink and start < 0:
			start = i
		elif not has_ink and start >= 0:
			out.append(Vector2i(start, i - start))
			start = -1
	if start >= 0:
		out.append(Vector2i(start, span - start))
	return out

## The tight box around everything with alpha.
func _ink_box(img: Image) -> Rect2i:
	var min_x: int = img.get_width()
	var min_y: int = img.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > ALPHA_FLOOR:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

func _mean_colour(img: Image) -> Color:
	var sum := Vector3.ZERO
	var n: int = 0
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.5:
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	if n <= 0:
		return Color(0, 0, 0, 0)
	var k: float = float(n)
	return Color(sum.x / k, sum.y / k, sum.z / k)

func _coverage(img: Image) -> float:
	var solid: int = 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				solid += 1
	return float(solid) / float(maxi(1, img.get_width() * img.get_height()))

## Tile the icons over MAGENTA. Magenta is the point: a square background, a halo or a blank cell is
## unmissable against it, where on the game board it would blend into the lighting and be missed.
func _write_contact(icons: Array[Image], side: int) -> void:
	var gap: int = 6
	var scale: int = maxi(1, 96 / side)
	var w: int = side * scale * icons.size() + gap * (icons.size() + 1)
	var h: int = side * scale + gap * 2
	var sheet: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(1.0, 0.0, 1.0, 1.0))
	for i in icons.size():
		var big: Image = icons[i].duplicate()
		if scale > 1:
			big.resize(side * scale, side * scale, Image.INTERPOLATE_NEAREST)
		sheet.blend_rect(big, Rect2i(0, 0, big.get_width(), big.get_height()),
			Vector2i(gap + i * (side * scale + gap), gap))
	sheet.save_png(CONTACT)
	print("[ElementIcons] contact sheet (on magenta, %dx magnified) -> %s" % [scale, CONTACT])
