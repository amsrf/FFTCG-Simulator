extends Node
## One-off: zoom into parts of references/editor.png.
##
## Follows png_probe.gd — the image tool hangs on this file, so the pixels are read directly:
##  (a) the deck-list panel at high resolution, to see what a row contains;
##  (b) the card grid's exact card and gap columns, by scanning a row through the middle of a card.

const PATH := "res://references/editor.png"
const PANEL_X0 := 1430

func _ready() -> void:
	var img := Image.new()
	if img.load(PATH) != OK:
		print("[PngZoom] load failed")
		get_tree().quit()
		return
	var w: int = img.get_width()
	var h: int = img.get_height()

	_print_hi_res(img, w, h)
	_scan_grid(img, w, h, 250)   # a scanline through the first row of cards
	_scan_grid(img, w, h, 620)   # and through the second
	_scan_rows(img, w, h)
	get_tree().quit()

## The right side, one character per 3x3 px, so a row's contents are ~10 characters tall.
func _print_hi_res(img: Image, w: int, h: int) -> void:
	var cw: int = 3
	var ch: int = 3
	print("[PngZoom] --- deck list panel, x >= %d, 1 char per %dx%d px ---" % [PANEL_X0, cw, ch])
	print("[PngZoom] legend: # black  + dark  - mid  . light  (space) white  R red  G green  B blue  Y yellow  O orange")
	var cx_start: int = PANEL_X0 / cw
	for cy in range(h / ch):
		var line: String = ""
		for cx in range(cx_start, w / cw):
			var c: Color = img.get_pixel(cx * cw, cy * ch)
			line += _classify(c)
		print("|" + line + "|")

func _classify(c: Color) -> String:
	var maxc: float = maxf(c.r, maxf(c.g, c.b))
	var minc: float = minf(c.r, minf(c.g, c.b))
	var sat: float = 0.0 if maxc <= 0.001 else (maxc - minc) / maxc
	if sat > 0.30 and maxc > 0.12:
		if c.r >= c.g and c.r >= c.b:
			return "O" if (c.g / maxf(c.r, 0.001)) > 0.5 else "R"
		if c.g >= c.r and c.g >= c.b:
			return "Y" if (c.r / maxf(c.g, 0.001)) > 0.7 else "G"
		return "B"
	if maxc < 0.10: return "#"
	if maxc < 0.25: return "+"
	if maxc < 0.55: return "-"
	if maxc < 0.85: return "."
	return " "

## Runs of "card face" (light) versus "background" along one scanline: gives card width and the gap.
func _scan_grid(img: Image, w: int, h: int, y: int) -> void:
	print("[PngZoom] --- scanline y=%d: card faces and gaps ---" % y)
	var runs: Array = []
	var in_face: bool = false
	var start: int = 0
	for x in range(w):
		var c: Color = img.get_pixel(x, y)
		var lum: float = (c.r + c.g + c.b) / 3.0
		var face: bool = lum > 0.45
		if face != in_face:
			if in_face:
				runs.append({"kind": "card", "start": start, "end": x - 1})
			else:
				runs.append({"kind": "gap", "start": start, "end": x - 1})
			start = x
			in_face = face
	if in_face:
		runs.append({"kind": "card", "start": start, "end": w - 1})
	var cards: Array = []
	for r in runs:
		var width: int = int(r["end"]) - int(r["start"]) + 1
		if r["kind"] == "card" and width > 40:
			cards.append(r)
			print("  card x %4d..%4d  width %3d" % [r["start"], r["end"], width])
		elif r["kind"] == "gap" and width > 4 and width < 200:
			print("  gap  x %4d..%4d  width %3d" % [r["start"], r["end"], width])
	if cards.size() >= 2:
		print("  => %d cards; pitch %d px" % [cards.size(), int(cards[1]["start"]) - int(cards[0]["start"])])

## Horizontal bands that look like card rows: average luminance per row.
func _scan_rows(img: Image, w: int, h: int) -> void:
	print("[PngZoom] --- row profile (average luminance of x 20..1400, per 10 px band) ---")
	var line: String = ""
	for y in range(0, h, 10):
		var total: float = 0.0
		var n: int = 0
		for x in range(20, 1400, 12):
			var c: Color = img.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
			n += 1
		var avg: float = total / maxf(n, 1)
		var bucket: String = " " if avg > 0.6 else ("." if avg > 0.35 else ("-" if avg > 0.15 else "#"))
		line += bucket
	print("|" + line + "|")
	print("[PngZoom] one char per 10 px of height; '#'=dark band, ' '=bright band  (row boundaries)")
