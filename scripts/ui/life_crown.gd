extends Node3D
## THE LIFE CRYSTALS: seven crystals growing out of the stones along a player's edge of the board, one per point of
## life (FF TCG: 7 damage loses). They BELONG TO THE BOARD: world-space, lit by the scene, fixed on the rocks
## in the reserved hand-Backup band (memory: hand-backup-band), each in a hewn basalt collar with an ember seam.
##
## Where: assets/board/layout.json (positions) + board_layout_baked.json (the ground under them, per seat, computed by
## Blender/build_board.py from the terrain it builds): a collar runs from below the LOWEST ground under it to above the
## HIGHEST, so it never floats and never sinks out of sight. Screen-left is world +x (the board camera looks toward
## +z), so index 0 is +x.
##
## Lean: the board camera looks down at ~67 degrees, so an upright crystal is foreshortened to ~40% of its height.
## Leaning the top back TOWARD THE FIELD (+z) by `lean_degrees` turns it toward the view (~74% at 25 degrees).
##
## When: a hit breaks crystals once the damage zoom hands the view back (Game.damage_zoom_finished), with a fallback
## timer for a hit with no zoom; `--fast` (PRESENTATION.fast_mode) syncs at once.
##
## Which: `BREAK_ORDER` - outermost left, outermost right, next left ... the centre crystal is the last life. The
## count is always read from the side (`damage_count()`), so healing restores crystals in reverse order. A broken
## crystal leaves a dark stub in its collar, so lost life is still countable.
##
## Geometry: assets/life_crown/life_crown.bin from Blender/build_life_crown.py (collar, ember seam, crystal).

const PRESENTATION := preload("res://scripts/core/presentation.gd")
const CRYSTAL_SHADER := preload("res://shaders/life_crystal.gdshader")
const HALO_SHADER := preload("res://shaders/life_crystal_halo.gdshader")
const BURST := preload("res://scripts/vfx/life_crystal_burst.gd")
const GEOMETRY_PATH := "res://assets/life_crown/life_crown.bin"

const LIVES := 7
const BREAK_ORDER: Array[int] = [0, 6, 1, 5, 2, 4, 3]
const STONE := 0
const EMBER := 1
const CRYSTAL := 2

## THE GROUND UNDER EACH CRYSTAL is computed by the board generator (Blender/build_board.py) from the same terrain
## function that builds the board, per seat (seat 2's board is turned 180 degrees), and written to this file:
## life_crystal_sockets[seat][edge] = [[x, z, lowest ground y, highest ground y], ...], listed from world +x to -x.
## The positions themselves come from assets/board/layout.json (life_crystals). Nothing here is copied by hand.
const BAKED_LAYOUT_PATH := "res://assets/board/board_layout_baked.json"

static func socket_sets() -> Dictionary:
	var f := FileAccess.open(BAKED_LAYOUT_PATH, FileAccess.READ)
	if f == null:
		push_error("LifeCrown: %s missing (run Blender/build_board.py)" % BAKED_LAYOUT_PATH)
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary) or not data.has("life_crystal_sockets"):
		push_error("LifeCrown: %s has no life_crystal_sockets" % BAKED_LAYOUT_PATH)
		return {}
	return data["life_crystal_sockets"]

## Crystal height and collar radius (m) by distance from the centre (0..3). The TOP edge is ~15% farther from the
## camera, so its crystals are sized to come out the SAME on screen (centre ~78 px); they stand on the far edge of the
## wood, pulled in toward the field, because past the wood there is only ~50 px before the opponent's hand.
const SIZES := {
	"bottom": [[0.56, 0.110], [0.48, 0.100], [0.43, 0.095], [0.38, 0.090]],
	"top": [[0.50, 0.100], [0.43, 0.092], [0.38, 0.087], [0.34, 0.082]],
}
## The two looks. Chaos: blood crystals in dark basalt (the volcanic edge). Cosmos: teal crystals in grey stone.
const STYLES := {
	"chaos": {"body": Color(0.42, 0.015, 0.03), "glow": Color(1.0, 0.07, 0.06), "ember": Color(1.0, 0.18, 0.06),
		"stone": Color(0.11, 0.105, 0.105)},
	"cosmos": {"body": Color(0.02, 0.30, 0.30), "glow": Color(0.12, 1.0, 0.85), "ember": Color(0.35, 1.0, 0.85),
		"stone": Color(0.30, 0.30, 0.31)},
}
## The collar's top stands this far above the highest rock under it; its foot this far below the lowest.
const COLLAR_ABOVE := 0.035
const COLLAR_BELOW := 0.02
## The crystal mesh is 1.0 tall and ~0.41 wide; it is drawn this much narrower so seven fit the band.
const CRYSTAL_SLIM := 0.7

## Top of each crystal leans back toward the field by this much (see the header).
@export var lean_degrees: float = 25.0
## Seconds between crystals when one hit takes several.
@export var stagger_seconds: float = 0.22
## The pre-burst beat: the crystal shakes and flashes white for this long, then explodes.
@export var crack_seconds: float = 0.14
## If no zoom reports back within this long after a hit, sync anyway.
@export var fallback_seconds: float = 4.0

var game = null
var side: PlayerSide = null
var style: String = "chaos"
var edge: String = "bottom"
## [x, z, low, high, crystal height, collar radius] per crystal, in the OWNER's left-to-right order.
var sockets: Array = []
var _crystals: Array[MeshInstance3D] = []
var _stubs: Array[MeshInstance3D] = []
var _halos: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _halo_mats: Array[ShaderMaterial] = []
var _rest: Array[Transform3D] = []
var _shown: int = 0           # damage currently drawn (crystals broken)
var _pending: bool = false
var _pending_serial: int = 0
var _breaking: Dictionary = {}  # crystal index -> true while its crack plays

## `p_edge` "bottom" (the local side) or "top"; `seat` picks the board the rocks were sampled on.
## ORDER: index 0 is the OWNER's leftmost crystal. The bottom owner faces +z, so their left is world +x (screen-left);
## the top owner faces -z, so their left is world -x (screen-right) and the list is reversed.
func setup(p_game, p_side: PlayerSide, p_style: String = "chaos", p_edge: String = "bottom", seat: int = 1) -> void:
	game = p_game
	side = p_side
	if _crystals.is_empty():
		style = p_style
		edge = p_edge
		sockets.clear()
		var sets: Dictionary = socket_sets()
		var seat_sets: Dictionary = sets.get(str(2 if seat == 2 else 1), {})
		var raw: Array = seat_sets.get(edge, [])
		if raw.size() != 7:
			push_error("LifeCrown: baked layout has %d sockets for seat %d %s (want 7)" % [raw.size(), seat, edge])
			return
		for k in range(raw.size()):
			var size: Array = SIZES[edge][absi(k - 3)]
			sockets.append((raw[k] as Array) + size)
		if edge == "top":
			sockets.reverse()
		_build()
	if side != null and not side.damaged.is_connected(_on_damaged):
		side.damaged.connect(_on_damaged)
	if game != null and game.has_signal("damage_zoom_finished") \
			and not game.damage_zoom_finished.is_connected(_on_zoom_finished):
		game.damage_zoom_finished.connect(_on_zoom_finished)
	_shown = 0
	for i in range(_crystals.size()):
		_set_alive(i, true)
	sync(false)

func _camera() -> Camera3D:
	if game != null and game.has_method("board_camera"):
		var cam: Camera3D = game.board_camera()
		if cam != null and is_instance_valid(cam):
			return cam
	return get_viewport().get_camera_3d()

## Screen rectangle the crystals and collars cover on the board camera (probe hook).
func screen_rect() -> Rect2:
	var cam := _camera()
	if cam == null or _rest.is_empty():
		return Rect2()
	var r := Rect2()
	var first := true
	for i in range(_rest.size()):
		var xf: Transform3D = _rest[i]
		var sock: Array = sockets[i]
		for p in [xf.origin, xf * Vector3(0, 1, 0), Vector3(sock[0], sock[2], sock[1])]:
			var sp: Vector2 = cam.unproject_position(p)
			r = Rect2(sp, Vector2.ZERO) if first else r.expand(sp)
			first = false
	return r

## World position of crystal `index`'s tip and foot (probe hook).
func crystal_tip(index: int) -> Vector3:
	return _rest[index] * Vector3(0, 1, 0)

func crystal_foot(index: int) -> Vector3:
	return _rest[index].origin

# ------------------------------------------------------------------ life
func lives_shown() -> int:
	var n := 0
	for i in range(_crystals.size()):
		if _crystals[i].visible and not _breaking.has(i):
			n += 1
	return n

func crystal_visible(index: int) -> bool:
	return index >= 0 and index < _crystals.size() and _crystals[index].visible

func _on_damaged(_side: PlayerSide) -> void:
	if PRESENTATION.fast_mode:
		sync(false)
		return
	_pending = true
	_pending_serial += 1
	var serial := _pending_serial
	await get_tree().create_timer(fallback_seconds).timeout
	if _pending and serial == _pending_serial:
		sync(true)

func _on_zoom_finished(zoomed: PlayerSide) -> void:
	if zoomed == side and _pending:
		sync(true)

## Draw the side's current damage. Breaks (or restores) the difference in BREAK_ORDER.
func sync(animate: bool = true) -> void:
	_pending = false
	if side == null or _crystals.is_empty():
		return
	var target: int = clampi(side.damage_count(), 0, LIVES)
	var zone: DamageZone = side.damage_zone
	if target > _shown:
		var delay := 0.0
		for k in range(_shown, target):
			var index: int = BREAK_ORDER[k]
			# The k-th damage card is what breaks the k-th crystal (zone.cards is in arrival order).
			var card: Card = zone.cards[k] if zone != null and k < zone.cards.size() else null
			if animate:
				_break_after(index, delay, k, card)
				delay += stagger_seconds
			else:
				if card != null:
					zone.park(card)
				_set_alive(index, false)
	elif target < _shown:
		for k in range(target, _shown):
			_set_alive(BREAK_ORDER[k], true)
	_shown = target

func _break_after(index: int, delay: float, serial: int, card: Card = null) -> void:
	_breaking[index] = true
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	# THE CARD GOES INTO THE CRYSTAL first: the revealed damage card flies to it, shrinking away, and the crystal
	# cracks as it arrives.
	if card != null and is_instance_valid(card) and side != null and side.damage_zone != null:
		var flight: Tween = side.damage_zone.absorb(card, _rest[index] * Vector3(0, 0.5, 0))
		if flight != null and flight.is_valid():
			await flight.finished
	var mat: ShaderMaterial = _mats[index]
	var crystal: MeshInstance3D = _crystals[index]
	var rest: Transform3D = _rest[index]
	var height: float = sockets[index][4]
	var t := 0.0
	# The crack: a quick rattle across the board and a rising white flash.
	while t < crack_seconds and is_inside_tree():
		var f: float = t / crack_seconds
		mat.set_shader_parameter("flash", f * f)
		_halo_mats[index].set_shader_parameter("flash", f)
		var jitter := Vector3(sin(t * 160.0), 0.0, cos(t * 133.0)) * 0.012 * height / 0.5
		crystal.transform = Transform3D(rest.basis, rest.origin + jitter)
		await get_tree().process_frame
		t += get_process_delta_time()
	crystal.transform = rest
	_breaking.erase(index)
	# Only burst if this crystal should still be broken (a heal may have arrived during the crack).
	if BREAK_ORDER.find(index) >= _shown:
		_set_alive(index, true)
		return
	_set_alive(index, false)
	var burst: Node3D = BURST.new()
	add_child(burst)
	# The burst is laid out in a camera-facing plane (its local XY = the screen), centred on the crystal's body.
	var cam := _camera()
	var facing: Basis = cam.global_basis.orthonormalized() if cam != null else Basis.IDENTITY
	burst.global_transform = Transform3D(facing, rest * Vector3(0, 0.5, 0))
	burst.burst(height, 7919 * (serial + 1) + index, STYLES[style]["body"], STYLES[style]["glow"])
	SoundManager.play(&"mana_crystal_shatter")

func _set_alive(index: int, alive: bool) -> void:
	_crystals[index].visible = alive
	_halos[index].visible = alive
	_stubs[index].visible = not alive
	_mats[index].set_shader_parameter("flash", 0.0)
	_halo_mats[index].set_shader_parameter("flash", 0.0)

# ------------------------------------------------------------------ build
func _build() -> void:
	var meshes := _load_meshes()
	if meshes.is_empty():
		return
	var stone := _stone()
	var ember := _ember()
	var look: Dictionary = STYLES[style]
	var stub_mat := _crystal_material(look)
	stub_mat.set_shader_parameter("alive", 0.0)
	var lean := Basis(Vector3.RIGHT, deg_to_rad(lean_degrees))
	for i in range(sockets.size()):
		var sock: Array = sockets[i]
		var x: float = sock[0]
		var z: float = sock[1]
		var low: float = sock[2]
		var high: float = maxf(sock[3], low + 0.05)
		var h: float = sock[4]
		var radius: float = sock[5]
		var bottom: float = low - COLLAR_BELOW
		var top: float = high + COLLAR_ABOVE
		# A fixed per-socket turn, so the seven collars do not show the same face.
		var turn := Basis(Vector3.UP, float(i) * 2.1)
		var collar_xf := Transform3D(turn.scaled(Vector3(radius, top - bottom, radius)), Vector3(x, bottom, z))
		for part in [[STONE, stone, "Collar%d"], [EMBER, ember, "Ember%d"]]:
			var mi := MeshInstance3D.new()
			mi.name = str(part[2]) % i
			mi.mesh = meshes.get(part[0])
			mi.material_override = part[1]
			mi.transform = collar_xf
			add_child(mi)
		# The crystal's foot sits in the collar's recess (the collar top centre is at 0.86 of its height).
		var foot := Vector3(x, bottom + (top - bottom) * 0.84, z)
		var rest := Transform3D(lean * Basis().scaled(Vector3(h * CRYSTAL_SLIM, h, h * CRYSTAL_SLIM)), foot)
		_rest.append(rest)
		var mat := _crystal_material(look)
		var c := MeshInstance3D.new()
		c.name = "Crystal%d" % i
		c.mesh = meshes.get(CRYSTAL)
		c.material_override = mat
		c.transform = rest
		add_child(c)
		# What a break leaves: the broken-off foot of the crystal, dark, a fifth of its height.
		var stub := MeshInstance3D.new()
		stub.name = "Stub%d" % i
		stub.mesh = meshes.get(CRYSTAL)
		stub.material_override = stub_mat
		stub.transform = Transform3D(lean * Basis().scaled(Vector3(h * CRYSTAL_SLIM, h * 0.2, h * CRYSTAL_SLIM)), foot)
		stub.visible = false
		add_child(stub)
		var halo := MeshInstance3D.new()
		halo.name = "Halo%d" % i
		var q := QuadMesh.new()
		q.size = Vector2(0.75, 1.15) * h
		halo.mesh = q
		var hm := ShaderMaterial.new()
		hm.shader = HALO_SHADER
		hm.set_shader_parameter("colour", look["glow"])
		hm.render_priority = 10
		halo.material_override = hm
		halo.position = rest * Vector3(0, 0.5, 0)
		add_child(halo)
		_crystals.append(c)
		_stubs.append(stub)
		_halos.append(halo)
		_mats.append(mat)
		_halo_mats.append(hm)
	_build_click_area()

## CLICK THE CRYSTALS TO SEE THE DAMAGE: the cards no longer lie in a row, so the crystal row is what opens the zone
## viewer (Game._show_zone_view, the same fan window a pile uses). One box round all seven collars and crystals.
func _build_click_area() -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in range(_rest.size()):
		var sock: Array = sockets[i]
		for p in [Vector3(sock[0], sock[2], sock[1]), _rest[i] * Vector3(0, 1, 0)]:
			lo = lo.min(p)
			hi = hi.max(p)
	lo -= Vector3(0.15, 0.05, 0.15)
	hi += Vector3(0.15, 0.05, 0.15)
	var area := Area3D.new()
	area.name = "ClickArea"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hi - lo
	shape.shape = box
	shape.position = (lo + hi) * 0.5
	area.add_child(shape)
	area.input_event.connect(_on_click)
	add_child(area)

func _on_click(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		open_damage_view()

## Open the zone viewer on this side's damage (probe hook, and what a click does).
func open_damage_view() -> void:
	if game == null or side == null or not game.has_method("_show_zone_view"):
		return
	var mine: bool = game.get("player") == side
	game._show_zone_view(side.damage_zone, "Damage Zone" if mine else "Opponent's Damage Zone")

func _load_meshes() -> Dictionary:
	var file := FileAccess.open(GEOMETRY_PATH, FileAccess.READ)
	if file == null or file.get_buffer(4).get_string_from_ascii() != "LCR1":
		push_error("LifeCrown: geometry missing or invalid at %s" % GEOMETRY_PATH)
		return {}
	var meshes := {}
	var mesh_count := file.get_32()
	for _m in range(mesh_count):
		var mid := file.get_32()
		var vcount := file.get_32()
		var icount := file.get_32()
		var pos := PackedVector3Array(); pos.resize(vcount)
		var nrm := PackedVector3Array(); nrm.resize(vcount)
		for i in range(vcount):
			pos[i] = Vector3(file.get_float(), file.get_float(), file.get_float())
			nrm[i] = Vector3(file.get_float(), file.get_float(), file.get_float())
		var idx := PackedInt32Array(); idx.resize(icount)
		for i in range(icount):
			idx[i] = file.get_32()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		if vcount > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		meshes[mid] = mesh
	return meshes

func _crystal_material(look: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CRYSTAL_SHADER
	m.set_shader_parameter("body", look["body"])
	m.set_shader_parameter("glow", look["glow"])
	return m

func _stone() -> StandardMaterial3D:
	# Chaos: basalt, matched by eye to the baked volcanic stones (the board is a baked render at 0.7 brightness, so
	# the collars are kept dark). Cosmos: plain grey stone.
	var m := StandardMaterial3D.new()
	m.albedo_color = STYLES[style]["stone"]
	m.roughness = 0.92
	m.metallic = 0.0
	return m

func _ember() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = STYLES[style]["ember"]
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
