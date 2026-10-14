extends Control
## CARD TILE PREVIEW — the tiles with real card art, laid out for judging, plus one on a 3D quad.
##
## HOW TO SEE IT
##   In the editor: open tests/card_tile_preview.tscn and press F6 (Run Current Scene).
##   From a terminal: godot res://tests/card_tile_preview.tscn
##
## WHAT IS ON SCREEN
##   Top row   — six tiles from the real database: Forward, damaged, dull, frozen, Backup, longest name.
##   Bottom    — two tiles side by side, the second with debug_show_crop ON, so art_region is drawn over the whole card and
##               you can see exactly what is being cropped away. This is the tuning aid.
##   Bottom-right — the same tile on a 3D QUAD, rendered through a SubViewport. THE BATTLEFIELD IS 3D AND A CONTROL CANNOT
##               LIVE THERE, so this bridge is how tiles reach the board: the Control draws, the SubViewport captures it,
##               and a mesh shows it. BigButton already does exactly this for its text. If the tile reads well here, it will
##               read well on the field.
##
## TUNING: everything worth touching is an @export on card_tile.gd — sizes, art_region, name font size, strip opacity,
## badge size and font, element_colors, texture filtering, and debug_show_crop. Select a tile in the running scene's remote
## tree (or the scene itself) and change it live.
##
## Nothing here touches game logic: it builds tiles from the database and shows them.

const TILE := preload("res://card_tile.tscn")
const CARD_VIEW := preload("res://scripts/card_view.gd")

## The tiles to draw, in order. Long names and every state worth judging at a glance.
const SAMPLES := [
	{"want": "Forward", "damage": 0,    "dull": false, "frozen": false, "note": "Forward, untouched"},
	{"want": "Forward", "damage": 2000, "dull": false, "frozen": false, "note": "Forward, damaged"},
	{"want": "Forward", "damage": 0,    "dull": true,  "frozen": false, "note": "Forward, dull"},
	{"want": "Forward", "damage": 1000, "dull": false, "frozen": true,  "note": "Forward, frozen"},
	{"want": "Backup",  "damage": 0,    "dull": false, "frozen": false, "note": "Backup - no badge"},
	{"want": "longest", "damage": 0,    "dull": false, "frozen": false, "note": "the longest name in the data"},
]

var _row: HBoxContainer
var _debug_row: HBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Translucent, NOT opaque: the 3D quad is drawn behind this Control, and a solid background would hide it.
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.14, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	var title := Label.new()
	title.text = "Card tiles - real art, cropped between the name bar and the rules text"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 18)
	column.add_child(_row)

	var notes := Label.new()
	notes.add_theme_font_size_override("font_size", 13)
	notes.text = "Bottom row: the crop overlay, off then ON - it draws art_region over the whole card.  Bottom right: the tile on a 3D quad."
	column.add_child(notes)

	_build_samples()
	_build_crop_debug_row()

	# The 3D half: without a camera NOTHING in 3D renders, which is why the first version of this scene showed no quad.
	_build_quad()


func _find_card(want: String) -> Dictionary:
	var db: Array = CardDatabase.card_database
	var longest: Dictionary = {}
	for i in range(db.size()):
		var e: Dictionary = db[i]
		var type: String = str(e.get("type_en", ""))
		if type != "Forward" and type != "Backup":
			continue
		e["_id"] = i + 1
		if str(e.get("name_en", "")).length() > str(longest.get("name_en", "")).length():
			longest = e
		if want == "longest":
			continue
		if type == want:
			return e
	return longest


## The element key of a database entry. NOT `(entry.get("element") or ["fire"])` — in GDScript `or` yields a BOOL, so that
## expression becomes `true[0]` the moment the left side is falsy, and the whole tile fails to build. Spelled out on
## purpose; it has already cost me one debugging round in this project.
func _element_of(entry: Dictionary) -> String:
	var raw = entry.get("element")
	if raw is Array:
		var list: Array = raw
		if not list.is_empty():
			return str(list[0])
	elif raw is String and not str(raw).is_empty():
		return str(raw)
	return "fire"


func _id_of(entry: Dictionary) -> int:
	return int(entry.get("_id", 1))


func _make_tile(entry: Dictionary, damage: int, dull: bool, frozen: bool) -> CardTile:
	var tile: CardTile = TILE.instantiate()
	var is_forward: bool = str(entry.get("type_en", "")) == "Forward"
	var element: String = _element_of(entry)
	tile.setup(_art(_id_of(entry)), str(entry.get("name_en", "?")), element,
		is_forward, str(entry.get("power", "")), damage)
	tile.set_dull(dull)
	tile.set_frozen(frozen)
	tile.set_highlight(not dull)
	return tile


func _build_samples() -> void:
	for sample in SAMPLES:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		_row.add_child(cell)
		var entry: Dictionary = _find_card(str(sample["want"]))
		var tile: CardTile = _make_tile(entry, int(sample["damage"]), bool(sample["dull"]), bool(sample["frozen"]))
		cell.add_child(tile)
		print("[Tile] %-24s id=%d art=%s element=%s forward=%s power=%s size=%s" % [
			str(sample["note"]), _id_of(entry), not CARD_VIEW.art_path(_id_of(entry)).is_empty(),
			_element_of(entry), str(entry.get("type_en", "")) == "Forward", entry.get("power", ""),
			tile.custom_minimum_size])
		var cap := Label.new()
		cap.text = str(sample["note"])
		cap.add_theme_font_size_override("font_size", 11)
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cap.custom_minimum_size = Vector2(144, 0)
		cell.add_child(cap)


## The tuning aid: the same tile twice, the second with the crop region drawn over the full card.
func _build_crop_debug_row() -> void:
	_debug_row = HBoxContainer.new()
	_debug_row.add_theme_constant_override("separation", 18)
	add_child(_debug_row)
	for flag in [false, true]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		_debug_row.add_child(cell)
		var entry: Dictionary = _find_card("Forward")
		var tile: CardTile = _make_tile(entry, 0, false, false)
		tile.debug_show_crop = bool(flag)
		cell.add_child(tile)
		var cap := Label.new()
		cap.add_theme_font_size_override("font_size", 11)
		cap.text = "debug_show_crop = %s" % flag
		cell.add_child(cap)


## THE FIELD BRIDGE: a Control tile rendered into a SubViewport, drawn on a mesh in 3D.
func _build_quad() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 224)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var entry: Dictionary = _find_card("Forward")
	var tile: CardTile = _make_tile(entry, 2000, false, false)
	viewport.add_child(tile)

	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.4, 0.98)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = viewport.get_texture()
	# Unshaded so the tile is judged as drawn, not relit by whatever the board's lighting is doing.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material_override = mat

	# Bottom-right of the screen, clear of the 2D rows. Tiles are drawn into the 3D world here, so where it lands is a
	# camera and transform question rather than a layout one.
	var holder := Node3D.new()
	holder.position = Vector3(1.9, -1.15, 0.0)
	holder.add_child(quad)
	add_child(holder)

	# A camera is REQUIRED. A scene with no Camera3D renders no 3D at all, however much is in it.
	var cam := Camera3D.new()
	cam.position = Vector3(1.9, -1.15, 3.0)
	cam.current = true
	add_child(cam)


## The art for a card id, or null when the scan is not on disk. CardView.art_path() already answers "" for "no art", so the
## filesystem is probed in exactly one place rather than here as well.
func _art(id: int) -> Texture2D:
	var path: String = CARD_VIEW.art_path(id)
	if path.is_empty():
		push_warning("[Tile] no art on disk for id %d" % id)
		return null
	return load(path) as Texture2D
