extends Node
## Traces the OUTLINE of cards in a screenshot, so the shape of a row can be settled from the actual RENDER instead of
## from arithmetic about where the cards ought to be. That difference has cost this project a lot of time: the camera
## maths and the picture have disagreed repeatedly, and the picture is the one that matters.
##
## For each column it finds the LOWEST pixel that looks like a card and prints the profile as text, one row per 16 px of
## screen height, so the curve is readable in the console. A card pixel here is GREY-ish — low saturation — because the
## board under the cards is strongly blue (#7f7fdf), which separates them without needing a vision model at all.
##
## Usage:
##   godot --headless res://tools/hand_outline.tscn -- <res path> [x_min] [x_max] [y_min] [y_max] [step]

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://tools/shots/foe1.png"
	var x_min: int = int(args[1]) if args.size() > 1 else 500
	var x_max: int = int(args[2]) if args.size() > 2 else 1450
	var y_min: int = int(args[3]) if args.size() > 3 else 0
	var y_max: int = int(args[4]) if args.size() > 4 else 300
	var step: int = int(args[5]) if args.size() > 5 else 12

	var img: Image = _load_image(path)
	if img == null:
		print("[Outline] could not read ", path)
		get_tree().quit(1)
		return
	x_max = mini(x_max, img.get_width())
	y_max = mini(y_max, img.get_height())
	print("[Outline] %s  %dx%d  columns %d..%d step %d, rows %d..%d" % [
		path, img.get_width(), img.get_height(), x_min, x_max, step, y_min, y_max])

	# The lowest card pixel in each column. -1 means the column had none in range.
	var xs: Array[int] = []
	var ys: Array[int] = []
	for x in range(x_min, x_max, step):
		var found: int = -1
		for y in range(y_max - 1, y_min - 1, -1):
			if _looks_like_card(img.get_pixel(x, y)):
				found = y
				break
		xs.append(x)
		ys.append(found)
	if xs.is_empty():
		print("[Outline] nothing to scan")
		get_tree().quit(1)
		return

	var band: int = 16
	print("[Outline] lowest card pixel per column, one row per %d px of screen height:" % band)
	for top in range(y_min, y_max, band):
		var row: String = ""
		for k in range(ys.size()):
			row += "#" if ys[k] >= top and ys[k] < top + band else "."
		print("[Outline] y %4d  %s" % [top, row])

	# THE TWO NUMBERS THE ARGUMENT IS ABOUT: where the ends sit against where the middle sits.
	var left: int = ys[0]
	var mid: int = ys[ys.size() / 2]
	var right: int = ys[ys.size() - 1]
	print("[Outline] left column x %d -> y %d | middle x %d -> y %d | right x %d -> y %d" % [
		xs[0], left, xs[ys.size() / 2], mid, xs[ys.size() - 1], right])
	if left >= 0 and mid >= 0 and right >= 0:
		var ends: int = (left + right) / 2
		print("[Outline] the ENDS sit %d px %s the MIDDLE (screen y grows downward)" % [
			absi(ends - mid), "BELOW" if ends > mid else "ABOVE"])
	get_tree().quit(0)

## Grey-ish and not black. Saturation alone separates a card from the blue board beneath it.
func _looks_like_card(c: Color) -> bool:
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	var mn: float = minf(c.r, minf(c.g, c.b))
	if mx < 0.15:
		return false
	return (mx - mn) <= 0.12

## Direct file read first: a screenshot written into tools/shots/ is not an imported resource, so load() can miss it.
func _load_image(path: String) -> Image:
	var direct: Image = Image.load_from_file(path)
	if direct != null:
		return direct
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	return tex.get_image()
