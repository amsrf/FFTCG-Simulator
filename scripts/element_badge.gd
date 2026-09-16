extends Node3D
class_name ElementBadge
## One crystal-cost badge: a circular disc carrying either an element's glyph or a numeral.
##
## TWO MODES, one disc:
##   * ELEMENT mode — `element` is "fire".."dark", or the CJK key the cards use ("火"), and the glyph
##     is drawn. A cost gives ONE BADGE PER ELEMENTAL POINT: three fire is three of these, because
##     that is how a player counts off what is still owed.
##   * NUMERAL mode — `number` >= 0 draws the value in place of a glyph. This is the NEUTRAL part of a
##     cost: neutral has no element of its own, so it is shown as a single badge with the number in it
##     rather than one badge per point.
##
## The glyphs come from assets/elements/*.png, built by tools/build_element_icons.gd from
## references/all-element.jpg. The badge keeps itself FACING THE CAMERA (see _align_to_camera): it is a
## flat quad meant to float above a player's head, and the board camera looks down at only ~11 degrees
## off vertical, so a fixed quad would be seen almost edge-on.

## fire, ice, wind, earth, lightning, water, light, dark — or the CJK key, e.g. "火".
@export var element: String = "fire":
	set(value):
		element = value
		_apply()

## 0 or more shows a NUMERAL instead of an element glyph (the neutral part of a cost). -1 keeps the
## badge in element mode.
@export var number: int = -1:
	set(value):
		number = value
		_apply()

## How wide the badge is in metres. At the board's orthographic scale (5.766 m across the viewport)
## 0.22 m is about 4% of the screen height — small enough to sit above a player's head.
@export var size_m: float = 0.22:
	set(value):
		size_m = value
		_apply()

const SHADER := preload("res://shaders/element_badge.gdshader")
const ICON_DIR := "res://assets/elements/"
const NUMERAL_FONT := preload("res://Font/FOT-NewRodin Pro EB.otf")
## How much of the disc a numeral may fill. The height is the target; the width is a cap, so a two- or
## three-digit neutral shrinks instead of spilling past the rim.
const NUMERAL_HEIGHT := 0.52
const NUMERAL_WIDTH := 0.68
const NUMERAL_FONT_SIZE := 64
## The neutral part has no element colour, so its ring is deliberately plain.
const NEUTRAL_ACCENT := Color(0.80, 0.82, 0.86)

## The sheet's order, and the two spellings of each element: the ASCII name used for the icon files and
## cost keys, and the CJK character the cards and the mana model use.
const ELEMENTS: Array[String] = ["fire", "ice", "wind", "earth", "lightning", "water", "light", "dark"]
const CJK: Array[String] = ["火", "氷", "風", "土", "雷", "水", "光", "闇"]
## The accent ring per element, in the sheet's own colours so the badge and the glyph agree.
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

var _material: ShaderMaterial = null
var _numeral: Label3D = null
var _blank: Texture2D = null

func _ready() -> void:
	_apply()
	_align_to_camera()

func _process(_delta: float) -> void:
	_align_to_camera()

## Cost Dictionaries key elements either by String ("fire", "neutral") or by a one-element Array
## (["火"]) — the latter because that is how `card.element` is stored. Both have to reach the same
## badge, so every key goes through here first.
static func key_to_element(key: Variant) -> String:
	if key is Array:
		var a: Array = key
		return str(a[0]) if a.size() > 0 else ""
	return str(key)

## Index of `element` in ELEMENTS, or -1 if it is neither an ASCII name nor a CJK key.
func element_index() -> int:
	var key: String = element.strip_edges()
	var i: int = ELEMENTS.find(key.to_lower())
	if i >= 0:
		return i
	return CJK.find(key)

## Face the camera. Matching the camera's BASIS but not its position keeps the badge where it is, while
## pointing the quad's +Z — which is the face of a QuadMesh — straight at the viewer. Done on the NODE
## rather than in the shader deliberately: a shader billboard would turn the disc but leave the numeral
## behind, and the two would drift apart as the camera moved.
func _align_to_camera() -> void:
	if not is_inside_tree():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		global_transform = Transform3D(cam.global_transform.basis, global_position)

## Re-reads the exports into the mesh, the material and the numeral. Every setter calls this, so
## assigning in code and dragging in the Inspector take the same path and cannot disagree.
func _apply() -> void:
	if not is_inside_tree():
		return
	var quad: MeshInstance3D = get_node_or_null("Quad")
	if quad == null:
		return
	var mesh: QuadMesh = quad.mesh as QuadMesh
	if mesh != null:
		mesh.size = Vector2(size_m, size_m)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		quad.material_override = _material
		# Element mode is the default here: NO DISC and NO RING, just the glyph. The readout is meant to read
		# as plain icons, and the accent ring — a good idea at 0.40 m — is pure noise at 26 px. The numeral
		# branch below turns the disc back on for itself.
		_material.set_shader_parameter("ring_width", 0.0)
		_material.set_shader_parameter("disc_amount", 0.0)

	if number >= 0:
		# NUMERAL: a flat WHITE disc with nothing on it but the number, which is baked in black. So the disc
		# is drawn, the ink is the glyph, and there is still no ring.
		if _blank == null:
			var img: Image = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			_blank = ImageTexture.create_from_image(img)
		_material.set_shader_parameter("disc_amount", 1.0)
		_material.set_shader_parameter("disc_color", Color(1.0, 1.0, 1.0, 1.0))
		_material.set_shader_parameter("element_icon", _blank)
		_show_numeral(number)
		return

	if _numeral != null:
		_numeral.visible = false
	var idx: int = element_index()
	if idx < 0:
		push_warning("[ElementBadge] unknown element '%s' — expected one of %s or %s"
			% [element, ", ".join(ELEMENTS), ", ".join(CJK)])
		return
	var tex: Texture2D = load(ICON_DIR + ELEMENTS[idx] + ".png")
	if tex == null:
		push_warning("[ElementBadge] could not load the icon for '%s' — has the project been opened "
			% ELEMENTS[idx] + "since tools/build_element_icons.gd wrote it? New PNGs need one import pass.")
		return
	_material.set_shader_parameter("element_icon", tex)
	_material.set_shader_parameter("ring_color", ACCENT[idx])

## The numeral is a baked TEXTURE on the quad, exactly like an element glyph — not a Label3D.
##
## The Label3D version rendered in an isolated asset scene but NOT in the game, at any size: the node was
## verified correct (text='1', visible=true, correct pixel size, parented properly, billboarded, and with
## no_depth_test set) while a 4x zoom shot of its badge showed a blank disc. An ImageTexture rides the
## code path the glyphs already prove works in both contexts, so it cannot fail that way.
##
## Numerals are baked 1..20 by tools/build_digit_textures.gd. A neutral cost above that has no texture and
## simply shows no number — re-run that tool with a wider range if costs can go higher.
func _show_numeral(value: int) -> void:
	var tex: Texture2D = load("%snum_%d.png" % [ICON_DIR, value])
	if tex == null:
		push_warning("[ElementBadge] no baked numeral for %d — tools/build_digit_textures.gd bakes 1..20; "
			% value + "re-run it if a neutral cost can go higher. Showing no number for now.")
		if _numeral != null:
			_numeral.visible = false
		return
	_material.set_shader_parameter("element_icon", tex)
