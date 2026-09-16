extends Node
## Bakes the numerals 0..99 into textures, so a cost badge can draw a number the exact same way it
## draws an element glyph.
##
## WHY THIS EXISTS: the neutral part of a cost is shown as a numeral, and the first implementation used a
## Label3D child. That renders in a plain asset scene but does NOT draw in the game, at any size —
## measured, not guessed: the node reported text='1', visible=true, a correct pixel_size, was parented
## correctly, billboarded itself, and had no_depth_test set, while a 4x zoom shot of its badge showed a
## blank disc. Baking the digits removes the whole class of problem: an ImageTexture on the quad goes
## through exactly the code path the element glyphs already use, in both contexts.
##
## RUN IT WINDOWED, like the shot harness — it must actually render to read the viewport back:
##   godot res://tools/build_digit_textures.tscn --quit-after 3000
##
## Output: assets/elements/num_0.png .. num_99.png, 256x256, white on transparent, trimmed to the ink
## and fitted by its longest side — the same convention as the element icons, so a "1" fills its badge
## the way the flame does.

const OUT_DIR := "res://assets/elements"
const CONTACT := "res://assets/elements/_digits_contact_sheet.png"
const FONT := preload("res://Font/FOT-NewRodin Pro EB.otf")
## 1..20, which covers a neutral cost in practice. The badge WARNS for a cost above LAST, so if this is
## ever widened the badge's warning text has to be widened with it.
const FIRST := 1
const LAST := 20
const TEX := 256
const FONT_SIZE := 190
const PAD_RATIO := 0.10

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var icons: Array[Image] = []
	for n in range(FIRST, LAST + 1):
		var img: Image = await _render_number(n)
		icons.append(img)
		img.save_png("%s/num_%d.png" % [OUT_DIR, n])
		if n <= FIRST + 2 or n == LAST:
			print("[DigitTextures] num_%d.png  %dx%d" % [n, img.get_width(), img.get_height()])
	_write_contact(icons)
	print("[DigitTextures] done — %d numerals in %s" % [COUNT, OUT_DIR])
	get_tree().quit()

## Draws the number in a SubViewport with a real Label, then reads the viewport texture back. Two
## frames are awaited: the first lays the Label out, the second guarantees the drawn result is the one
## that gets read.
func _render_number(n: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(TEX, TEX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var label := Label.new()
	label.text = str(n)
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	# BLACK, because the numeral now sits on a plain white disc with no border — white-on-white would be
	# invisible. The disc colour is the badge shader's business; this only bakes the ink.
	label.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(label)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shot: Image = vp.get_texture().get_image()
	vp.queue_free()

	# White on transparent: the ink IS the alpha, so the bounds come straight off it.
	var box: Rect2i = _ink_box(shot)
	if box.size.x <= 0 or box.size.y <= 0:
		push_warning("[DigitTextures] nothing was drawn for %d" % n)
		return shot
	var side: int = int(maxf(box.size.x, box.size.y) * (1.0 + PAD_RATIO * 2.0))
	var cx: float = float(box.position.x) + box.size.x * 0.5
	var cy: float = float(box.position.y) + box.size.y * 0.5
	var x: int = clampi(int(cx - side * 0.5), 0, TEX - mini(side, TEX))
	var y: int = clampi(int(cy - side * 0.5), 0, TEX - mini(side, TEX))
	side = mini(side, TEX)
	var out: Image = shot.get_region(Rect2i(x, y, side, side))
	out.resize(TEX, TEX, Image.INTERPOLATE_LANCZOS)
	return out

## The tight box around everything with alpha, which for white-on-transparent is the whole glyph.
func _ink_box(img: Image) -> Rect2i:
	var min_x: int = img.get_width()
	var min_y: int = img.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.03:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, maxi(0, max_x - min_x + 1), maxi(0, max_y - min_y + 1))

## Tile every tenth numeral over magenta, same diagnostic as the element icons: a blank bake or a
## mis-sized one is obvious at a glance.
func _write_contact(icons: Array[Image]) -> void:
	var picks: Array[int] = [0, 1, 2, 3, 5, 8, 10, 12, 25, 47, 99]
	var gap: int = 6
	var w: int = TEX * picks.size() + gap * (picks.size() + 1)
	var h: int = TEX + gap * 2
	var sheet: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(1.0, 0.0, 1.0, 1.0))
	for i in picks.size():
		var n: int = picks[i]
		# icons[] is indexed from FIRST, so the numeral has to be offset back to 0 before indexing.
		var at: int = n - FIRST
		if at >= 0 and at < icons.size():
			sheet.blend_rect(icons[at], Rect2i(0, 0, TEX, TEX), Vector2i(gap + i * (TEX + gap), gap))
	sheet.save_png(CONTACT)
	print("[DigitTextures] contact sheet (%s) -> %s"
		% [", ".join(picks.map(func(v): return str(v))), CONTACT])
