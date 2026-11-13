extends RefCounted
## KEYWORD ICONS: one small badge per keyword the card HAS right now (printed, granted, timed or code), laid in a row
## along the bottom of the card face starting from the left. Pure presentation: each badge asks the same predicate the
## rules ask (Card.is_brave(), Card.is_first_strike()), so a grant or a silence shows up the next time refresh() runs.
## Owned by Card as `card.keyword_icons`; Card.refresh_keyword_icons() is the one caller.
##
## All badges share one look — a white glyph on a black rounded plate with a white rim — so a new keyword is one more
## glyph in tools/build_keyword_icons.py (which writes the SVG into assets/icons/keywords/) and one more row in KEYWORDS.
##
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the global cache.

## Row order, left to right. [keyword, icon path, Card predicate].
const KEYWORDS: Array = [
	["brave", "res://assets/icons/keywords/brave.svg", "is_brave"],
	["first_strike", "res://assets/icons/keywords/first_strike.svg", "is_first_strike"],
	["indestructible", "res://assets/icons/keywords/indestructible.svg", "is_unbreakable"],
	["cannot_block", "res://assets/icons/keywords/cannot_block.svg", "is_block_disabled"],
]

## Badge width as a fraction of the card face width, the inset from the left/bottom edges, and the gap between badges.
const ICON_FRACTION := 0.23
const EDGE_MARGIN_FRACTION := 0.035
const GAP_FRACTION := 0.015
## Above the face, the cost badge (0.0015) and the frozen rim (0.003), so nothing on the card fights it for depth.
const LIFT := 0.0035
## Pixels per SVG unit when the badge is rasterized at runtime: 128-unit art -> a 256 px texture with mipmaps, so the
## brush strokes stay crisp on a hovered/zoomed card and the mipmaps keep them clean at board size.
const RASTER_SCALE := 2.0

static var _textures: Dictionary = {}

## Card is a Node3D; kept untyped so this file and card.gd do not depend on each other's class_name.
var _card: Node3D
var _row: Node3D = null
var _badges: Dictionary = {}   # keyword -> MeshInstance3D

func _init(card: Node3D) -> void:
	_card = card

## The keywords currently shown, in row order. Probe hook.
func shown() -> Array[String]:
	var out: Array[String] = []
	if _row == null or not is_instance_valid(_row) or not _row.visible:
		return out
	for entry in KEYWORDS:
		var badge: MeshInstance3D = _badges.get(entry[0]) as MeshInstance3D
		if badge != null and badge.visible:
			out.append(String(entry[0]))
	return out

## Badge node for a keyword (null if never built). Probe hook.
func badge(keyword: String) -> MeshInstance3D:
	return _badges.get(keyword) as MeshInstance3D

## `visible_on_card` is the card's own "is the printed face what is on screen" answer (field, face up, landed, not
## dissolving); the row lays out only the keywords the card has, so there is never a hole on the left.
func refresh(visible_on_card: bool) -> void:
	var wanted: Array = []
	if visible_on_card:
		for entry in KEYWORDS:
			if _card.has_method(entry[2]) and bool(_card.call(entry[2])):
				wanted.append(entry)
	if wanted.is_empty():
		if _row != null and is_instance_valid(_row):
			_row.visible = false
		return
	_ensure_row()
	var face: Vector2 = _card._card_face_size()
	var margin: float = face.x * EDGE_MARGIN_FRACTION
	var gap: float = face.x * GAP_FRACTION
	# Full size while the row fits; past that (four badges do not), every badge shrinks so the row stays on the card.
	var fit: float = (face.x - 2.0 * margin - (wanted.size() - 1) * gap) / wanted.size()
	var size: float = minf(face.x * ICON_FRACTION, fit)
	for entry in KEYWORDS:
		var b: MeshInstance3D = _badges.get(entry[0]) as MeshInstance3D
		if b != null:
			b.visible = false
	for i in wanted.size():
		var b: MeshInstance3D = _ensure_badge(wanted[i], size)
		# The face is a quad in XZ centred on the origin; the card's top is -Z, so the bottom edge is +face.y/2.
		b.position = Vector3(-face.x * 0.5 + margin + size * 0.5 + i * (size + gap), 0.0, face.y * 0.5 - margin - size * 0.5)
		b.visible = true
	_row.visible = true

func _ensure_row() -> void:
	if _row != null and is_instance_valid(_row):
		return
	_row = Node3D.new()
	_row.name = "KeywordIcons"
	var top: float = 0.0
	var hand_mesh = _card.hand_mesh
	if hand_mesh != null and hand_mesh.mesh != null:
		top = hand_mesh.mesh.get_aabb().end.y
	_row.position = Vector3(0.0, top + LIFT, 0.0)
	# Same parent as the frozen rim and the target ring: the visible card's mesh, so the damage recoil (a HandMesh
	# tween) carries the badges with the card.
	var parent: Node3D = (hand_mesh as Node3D) if hand_mesh != null else _card
	parent.add_child(_row)

func _ensure_badge(entry: Array, size: float) -> MeshInstance3D:
	var keyword: String = entry[0]
	var b: MeshInstance3D = _badges.get(keyword) as MeshInstance3D
	if b != null and is_instance_valid(b):
		(b.mesh as PlaneMesh).size = Vector2(size, size)
		return b
	var plane := PlaneMesh.new()   # in the card's XZ plane, facing +Y like the face; UV v=0 is the top (-Z)
	plane.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _texture(entry[1])
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Drawn after the card's ring (and the cost badge at 1), so a glow never washes over the badge.
	material.render_priority = 2
	b = MeshInstance3D.new()
	b.name = "Keyword_" + keyword
	b.mesh = plane
	b.material_override = material
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_row.add_child(b)
	_badges[keyword] = b
	return b

## Rasterize the SVG SOURCE whenever it can be read (the editor, a headless run): it is always the current drawing at
## RASTER_SCALE, while an editor import can be stale or 1x. An exported build ships only the import (the .import files
## ask for svg/scale 2 + mipmaps), so that is the fallback. Cached per path: every card shares one texture per keyword.
static func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string(path), RASTER_SCALE) == OK:
			image.generate_mipmaps()
			tex = ImageTexture.create_from_image(image)
	if tex == null and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		push_error("Keyword icon could not be loaded: %s" % path)
		return null
	_textures[path] = tex
	return tex
