extends Node
## Verifies the element badges' PLUMBING, not their look.
##
## What this can check: all eight elements resolve from both spellings the game uses (the ASCII cost key
## and the CJK character a card writes), the accent table covers every element, each icon texture
## loads and is the size the badge assumes, and changing `element` really swaps the glyph on the
## material rather than only changing a field.
##
## What it cannot check: how the badge looks. That needs a GPU and an eye — headless runs never draw.

const BADGE := preload("res://element_badge.tscn")
const ROW := preload("res://crystal_cost.tscn")

var _checked: int = 0
var _failed: int = 0

func _expect(ok: bool, what: String) -> void:
	_checked += 1
	if ok:
		print("[ElementBadgeProbe]  ok  %s" % what)
	else:
		_failed += 1
		print("[ElementBadgeProbe] FAIL %s" % what)

func _ready() -> void:
	print("[ElementBadgeProbe] ---- element badges ----")
	var names: Array = ["fire", "ice", "wind", "earth", "lightning", "water", "light", "dark"]
	var cjk: Array = ["火", "氷", "風", "土", "雷", "水", "光", "闇"]

	var badge: Node3D = BADGE.instantiate()
	_expect(badge != null and badge.has_method("element_index"),
		"element_badge.tscn instantiates with scripts/element_badge.gd attached")
	if badge == null:
		print("[ElementBadgeProbe] RESULT: 1 check(s) FAILED")
		return
	add_child(badge)
	var consts: Dictionary = badge.get_script().get_script_constant_map()

	# BOTH SPELLINGS. A cost Dictionary is keyed by the CJK character ('火'), while the icon files are
	# named in ASCII, so a badge that only understood one of them would fail the moment it met a real
	# cost — and it would fail quietly.
	for i in names.size():
		badge.set("element", names[i])
		_expect(badge.call("element_index") == i, "%-9s resolves by name" % names[i])
		badge.set("element", cjk[i])
		_expect(badge.call("element_index") == i, "%s resolves by its CJK key ('%s')" % [cjk[i], names[i]])

	# The accent table has to line up with the element list, or every badge gets its neighbour's colour.
	var accents: Array = consts.get("ACCENT", [])
	var listed: Array = consts.get("ELEMENTS", [])
	_expect(accents.size() == listed.size() and listed.size() == names.size(),
		"the accent ring and the element list are the same length (%d)" % accents.size())

	# An unknown element must be rejected rather than silently drawing something.
	badge.set("element", "plasma")
	_expect(badge.call("element_index") == -1, "an unknown element resolves to -1 instead of guessing")

	# THE GLYPH ITSELF. This is the check that notices a missing import pass: the PNGs the builder
	# writes are not loadable until Godot has imported them once.
	var quad: MeshInstance3D = badge.get_node_or_null("Quad")
	var mat: ShaderMaterial = quad.material_override if quad != null else null
	_expect(mat != null and mat.shader != null, "the badge builds its ShaderMaterial on demand")
	if mat != null:
		badge.set("element", "fire")
		var fire_tex: Texture2D = mat.get_shader_parameter("element_icon")
		_expect(fire_tex != null,
			"the fire glyph is bound — needs one editor/import pass after the builder writes it")
		if fire_tex != null:
			print("[ElementBadgeProbe] fire icon is %dx%d" % [fire_tex.get_width(), fire_tex.get_height()])
			# SQUARE and NATIVE, not a hardcoded size. The icons are cut out of the sheet at their own
			# ~26 px and only trimmed/re-centred, because that is the size they are displayed at — so the
			# old "must be 256x256" assertion was measuring the wrong thing entirely.
			_expect(fire_tex.get_width() == fire_tex.get_height() and fire_tex.get_width() <= 64,
				"the icons are square and near their native pixel size, not upscaled")
		# ELEMENT MODE DRAWS NO DISC AND NO RING: the icons are used as they are, so what shows is the
		# icon's own alpha. These are the shader parameters that decide it.
		var disc_amt: Variant = mat.get_shader_parameter("disc_amount")
		var ring_w: Variant = mat.get_shader_parameter("ring_width")
		_expect(disc_amt is float and absf(float(disc_amt)) < 0.001,
			"an element badge draws the glyph alone, with no disc behind it")
		_expect(ring_w is float and absf(float(ring_w)) < 0.001,
			"and no ring around it")
		badge.set("element", "water")
		var water_tex: Texture2D = mat.get_shader_parameter("element_icon")
		_expect(water_tex != null and water_tex != fire_tex,
			"changing the element actually swaps the glyph texture")

	badge.free()

	# ---- the cost row ---------------------------------------------------------------------------
	# Red Mage is a 2-cost fire card, so its cost is {'火': 1, 'neutral': 1}. That must read as ONE fire
	# badge followed by ONE numeral badge showing 1 — the elemental part one badge per point, the
	# neutral part a single badge with the number, because neutral has no glyph to repeat.
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true

	var row: Node3D = ROW.instantiate()
	_expect(row != null and row.has_method("badges"), "crystal_cost.tscn instantiates")
	if row != null:
		add_child(row)
		row.set("badge_size_m", 0.22)

		row.set("cost", {"火": 1, "neutral": 1})
		var list: Array = row.call("badges")
		_expect(list.size() == 2, "Red Mage {'火':1,'neutral':1} lays out two badges, not one per point")
		if list.size() == 2:
			var fire: Node3D = list[0]
			var one: Node3D = list[1]
			_expect(fire.get("element") == "火" and int(fire.get("number")) < 0,
				"the first badge is the fire glyph")
			_expect(int(one.get("number")) == 1, "the second badge is a NUMERAL badge showing 1")
			_expect(fire.position.x < one.position.x,
				"elemental badges come before the neutral numeral")
			# The numeral is a baked TEXTURE, not a Label3D. The label version rendered in an asset scene
			# but never in the game, so what has to be true now is that the numeral badge has its disc ON,
			# in white, and is holding a digit texture rather than an element glyph.
			var one_quad: MeshInstance3D = one.get_node_or_null("Quad")
			var one_mat: ShaderMaterial = one_quad.material_override if one_quad != null else null
			_expect(one_mat != null, "the numeral badge has its own material")
			if one_mat != null:
				var n_disc: Variant = one_mat.get_shader_parameter("disc_amount")
				var n_col: Variant = one_mat.get_shader_parameter("disc_color")
				var n_tex: Texture2D = one_mat.get_shader_parameter("element_icon")
				_expect(n_disc is float and float(n_disc) > 0.999,
					"a numeral badge turns the disc back ON, since black ink needs something to sit on")
				_expect(n_col is Color and float(n_col.r) > 0.99 and float(n_col.g) > 0.99
					and float(n_col.b) > 0.99,
					"and that disc is plain white, with no border")
				_expect(n_tex != null and n_tex != load("res://assets/elements/fire.png"),
					"and it holds a DIGIT texture rather than an element glyph")
				_expect(one.get_node_or_null("Numeral") == null or not one.get_node("Numeral").visible,
					"no Label3D numeral is being drawn — that path does not render in the game")
		_expect(row.get_node_or_null("PayLabel") != null,
			"the row carries its 'Pay' label, on the zero side of the badges")

		# One badge per POINT: two fire is two fire badges and no numeral.
		row.set("cost", {"火": 2})
		var two: Array = row.call("badges")
		_expect(two.size() == 2 and int(two[0].get("number")) < 0 and int(two[1].get("number")) < 0,
			"a 2-fire cost is two fire badges rather than one badge saying 2")

		# Neutral alone: ONE badge with the number, whatever the number is.
		row.set("cost", {"neutral": 5})
		var five: Array = row.call("badges")
		_expect(five.size() == 1 and int(five[0].get("number")) == 5,
			"five neutral is ONE badge showing 5, not five badges")

		# Both spellings of an element key, because Card.get_cost() keys them by Array.
		row.set("cost", {["氷"]: 1})
		var arr: Array = row.call("badges")
		_expect(arr.size() == 1 and arr[0].get("element") == "氷",
			"an Array key (['氷']) reaches the badge, not just a String key")

		# And it faces the camera, since it will hang above a player's head.
		row.call("_align_to_camera")
		var facing: float = row.global_transform.basis.z.dot(camera.global_transform.basis.z)
		print("[ElementBadgeProbe] cost row faces the camera with z-alignment %+.3f" % facing)
		_expect(facing > 0.99, "the cost row turns to face the camera rather than sitting edge-on")
		row.free()

	print("[ElementBadgeProbe] checked %d, failed %d" % [_checked, _failed])
	print("[ElementBadgeProbe] RESULT: %s"
		% ("all checks passed" if _failed == 0 else "%d check(s) FAILED" % _failed))
