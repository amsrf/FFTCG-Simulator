extends Node3D
## One board button sitting in a well of a button station (the housing is baked into the board; see
## Blender/build_button_housing.py). The button is a LENS — two shallow domes joined at a thin metal bezel — on an axle
## along local X. The +Y dome is the gem, with the label or a symbol IMPRINTED in white (shaders/disc_face.gdshader);
## the -Y dome is carved stone. It fills its well, so its rim tucks under the station's iron ring: no gap.
##
## A button is never hidden. It TURNS, and always FORWARD (rotation only ever increases): gem-up when offered, stone-up
## when not. A press always spins it: a half turn if the press takes it away, a full 360 if it stays offered.
##
## The disc is SHARED. Several logical buttons may claim it (Confirm and Pass both use the large one); it shows its gem
## while ANY claimant wants it. Claims are COALESCED to the end of the frame: Assistant routinely hides and re-shows a
## button within one frame (show_modal() hides everything first), and turning on each call would make it twitch.
##
## Hover lights the ring around the button (an additive annulus over the baked iron ring, shaders/disc_ring_glow);
## a press flashes it.

const HALF_TURN_SECONDS := 0.42
const FULL_TURN_SECONDS := 0.7
const GLOW_FADE_SECONDS := 0.15
const HOVER_GLOW := 1.0
const PRESS_GLOW := 1.8
const IMPRINT_SIZE := 512
const IMPRINT_FONT_SIZE := 92
const IMPRINT_MIN_FONT_SIZE := 40
## The text's box, as a fraction of the imprint: inside the metal band (which starts at 0.84 of the radius). ONE
## number for both the label's size and the fitting, or the fit measures a box the label does not have and wraps.
const TEXT_WIDTH := 0.58
const TEXT_HEIGHT := 0.42
## The station's iron ring sits this far above the disc's axle, and this far outside its rim (Blender constants:
## HOUSING_TOP - DISC_Z, and ring radius r + GAP + 0.012 against the disc's r + GAP - 0.002).
const RING_HEIGHT := 0.03
const RING_OUTSET := 0.014
const AXLE_LIFT := 0.02

const FACE_SHADER := preload("res://shaders/disc_face.gdshader")
const GLOW_SHADER := preload("res://shaders/disc_ring_glow.gdshader")

## The disc's radius: it fills the well (the well is this + 0.002).
@export var radius: float = 0.314
## What the gem carries: the claimant's TEXT (its meaning changes: Pass / Next Phase / Confirm…), or a fixed SYMBOL.
@export_enum("text", "symbol") var imprint_mode: String = "text"
## The symbol, and the text fallback: "play" (go forward) or "cross" (decline).
@export_enum("play", "cross") var glyph: String = "play"
## Colours are LINEAR, the same numbers as the Blender mock-up; converted when applied.
@export var gem_color: Color = Color(0.0, 0.26, 0.25)
@export var gem_emission: Color = Color(0.02, 0.55, 0.50)
@export var gem_energy: float = 0.6
@export var stone_color: Color = Color(0.035, 0.034, 0.036)
@export var groove_color: Color = Color(0.16, 0.15, 0.14)
@export var glow_color: Color = Color(0.3, 1.0, 0.85)
@export var imprint_font: Font

var _claims: Dictionary = {}          # claimant (Object) -> bool
var _texts: Dictionary = {}           # claimant -> String
var _last_claimant: Object = null     # the most recent claimant to turn ON: its text is imprinted
var _active := false                  # the state the disc has been sent to
var _goal := PI                       # the angle it is heading to (only ever increases between normalisations)
var _spin_pending := false
var _dirty := false
var _hovered := false
var _imprinted := ""                  # what the imprint currently shows
var _imprint_drawn := false           # whether the imprint has been drawn at all
var _turn_tween: Tween
var _glow_tween: Tween

var _pivot: Node3D
var _gem_material: ShaderMaterial
var _stone_material: ShaderMaterial
var _bezel_material: StandardMaterial3D
var _glow_material: ShaderMaterial
var _viewport: SubViewport
var _label: Label
var _symbol: Node2D


func _ready() -> void:
	_build()
	_pivot.rotation.x = PI      # starts stone-up: nothing has claimed it yet
	_apply_colors()


# --------------------------------------------------------------------------------------------- claims

## A logical button says whether it currently wants this disc lit, and what it should read.
func set_claim(claimant: Object, wants: bool, text: String = "") -> void:
	var was: bool = bool(_claims.get(claimant, false))
	_claims[claimant] = wants
	_texts[claimant] = text
	if wants and not was:
		_last_claimant = claimant
	_mark_dirty()

## The state the disc has been sent to (it may still be turning).
func is_active() -> bool:
	return _active

## The state it will be sent to at the end of this frame. Probes read this, not the rotation.
func wants_active() -> bool:
	for c in _claims:
		if _claims[c]:
			return true
	return false

## What the gem's imprint reads (empty for a symbol).
func label_text() -> String:
	return _label.text if _label != null and imprint_mode == "text" else ""

func set_hovered(on: bool) -> void:
	_hovered = on
	_glow_to(HOVER_GLOW if on else 0.0)

## A press: the ring flashes and the button spins (decided at the end of the frame, once the press's own
## effects — usually hiding this very button — have landed).
func pulse() -> void:
	_spin_pending = true
	if _glow_material != null:
		_glow_material.set_shader_parameter("intensity", PRESS_GLOW)
		_glow_to(HOVER_GLOW if _hovered else 0.0, 0.45)
	_mark_dirty()

func set_colors(gem: Color, emission: Color, stone: Color, groove: Color, glow: Color) -> void:
	gem_color = gem; gem_emission = emission; stone_color = stone; groove_color = groove; glow_color = glow
	_apply_colors()


func _mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_apply.call_deferred()

func _apply() -> void:
	_dirty = false
	var target := wants_active()
	_refresh_imprint(target)
	var goal := _goal
	if _spin_pending:
		# At least one half turn past where it was heading: an extra full turn when the state does not change.
		goal = _next_angle(_goal + 0.01, target)
	elif target != _active:
		goal = _next_angle(_goal, target)
	_spin_pending = false
	_active = target
	if is_equal_approx(goal, _goal):
		return
	var from := _pivot.rotation.x
	_goal = goal
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	var seconds := FULL_TURN_SECONDS if goal - from > PI * 1.5 else HALF_TURN_SECONDS
	_turn_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_turn_tween.tween_property(_pivot, "rotation:x", goal, seconds)
	_turn_tween.tween_callback(_normalise)

## The next angle at or beyond `from` that shows the wanted face: gem-up at even multiples of PI, stone-up at odd.
func _next_angle(from: float, gem_up: bool) -> float:
	var k := int(ceil(from / PI - 1e-4))
	if (k % 2 == 0) != gem_up:
		k += 1
	return k * PI

## Keep the angle small once a turn has landed, so it never grows without bound.
func _normalise() -> void:
	var wrapped := fposmod(_goal, TAU)
	if is_equal_approx(wrapped, TAU):
		wrapped = 0.0
	_pivot.rotation.x = wrapped
	_goal = wrapped

func _glow_to(value: float, seconds: float = GLOW_FADE_SECONDS) -> void:
	if _glow_material == null:
		return
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_method(func(v: float): _glow_material.set_shader_parameter("intensity", v),
		float(_glow_material.get_shader_parameter("intensity")), value, seconds)


# --------------------------------------------------------------------------------------------- imprint

func _refresh_imprint(target: bool) -> void:
	if _viewport == null:
		return
	var text := ""
	if imprint_mode == "text" and target:
		var who: Object = _last_claimant if bool(_claims.get(_last_claimant, false)) else null
		if who == null:
			for c in _claims:
				if _claims[c]:
					who = c
					break
		text = str(_texts.get(who, ""))
	# Turning OFF keeps the old text: the gem is going face-down and should not change on its way.
	if not target and _imprint_drawn:
		return
	if _imprint_drawn and text == _imprinted:
		return
	_imprint_drawn = true
	_imprinted = text
	_label.text = text
	_label.visible = not text.is_empty()
	_symbol.visible = text.is_empty()
	if not text.is_empty():
		_fit_label()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## Shrink the font until the text fits the dome: two lines at most, inside the circle.
func _fit_label() -> void:
	var font: Font = _label.get_theme_font("font")
	var width := IMPRINT_SIZE * TEXT_WIDTH
	var size := IMPRINT_FONT_SIZE
	while size > IMPRINT_MIN_FONT_SIZE:
		var block := font.get_multiline_string_size(_label.text, HORIZONTAL_ALIGNMENT_CENTER, width, size)
		if block.x <= width and block.y <= IMPRINT_SIZE * TEXT_HEIGHT:
			break
		size -= 4
	_label.add_theme_font_size_override("font_size", size)


# --------------------------------------------------------------------------------------------- build

func _build() -> void:
	_pivot = Node3D.new(); _pivot.name = "Pivot"
	# The axle rides a little above the well's centre line, so the rim sits just under the ring's lip rather than
	# leaving a dark band of well wall showing inside it.
	_pivot.position.y = AXLE_LIFT
	add_child(_pivot)
	var dome_height := radius * 0.26     # thick enough for the gem's setting to read as a step

	_build_imprint()
	_gem_material = ShaderMaterial.new(); _gem_material.shader = FACE_SHADER
	_gem_material.set_shader_parameter("use_imprint", true)
	_gem_material.set_shader_parameter("crystal", true)
	_gem_material.set_shader_parameter("emission_energy", gem_energy)
	_gem_material.set_shader_parameter("imprint", _viewport.get_texture())
	_stone_material = ShaderMaterial.new(); _stone_material.shader = FACE_SHADER
	_stone_material.set_shader_parameter("roughness", 0.85)
	_stone_material.set_shader_parameter("groove_radius", 0.48)

	# A unit hemisphere (y 0..1): the shader projects the imprint from its x/z.
	var dome := SphereMesh.new()
	dome.radius = 1.0; dome.height = 2.0; dome.is_hemisphere = true
	# 128 around keeps the outline a circle at ~200 px; 96 rings put several rings across the setting's 0.03-wide wall
	# (48 put fewer than two there, so the vertex-displaced step was a coarse zigzag).
	dome.radial_segments = 128; dome.rings = 96
	var gem := _add_mesh("GemDome", dome, _gem_material)
	gem.scale = Vector3(radius, dome_height, radius)
	var stone := _add_mesh("StoneDome", dome, _stone_material)
	stone.rotation.x = PI
	stone.scale = Vector3(radius, dome_height, radius)

	_bezel_material = StandardMaterial3D.new()
	_bezel_material.albedo_color = Color(0.82, 0.84, 0.88)
	_bezel_material.metallic = 1.0
	# Rougher than a mirror on purpose: a thin, tightly curved chrome tube packs its highlight into a pixel or two,
	# which flickers and steps no matter how many MSAA samples there are (specular aliasing).
	_bezel_material.roughness = 0.45
	var bezel := TorusMesh.new()
	# ~0.02 m wide: thick enough to stay 3+ px from the board camera.
	bezel.inner_radius = radius - 0.02; bezel.outer_radius = radius
	bezel.rings = 128; bezel.ring_segments = 12
	_add_mesh("Bezel", bezel, _bezel_material)

	# The ring glow belongs to the STATION, not the button: it is a child of the socket, not of the pivot.
	var reach := radius + RING_OUTSET + 0.09
	var quad := PlaneMesh.new()
	quad.size = Vector2(reach * 2.0, reach * 2.0)
	_glow_material = ShaderMaterial.new(); _glow_material.shader = GLOW_SHADER
	_glow_material.set_shader_parameter("ring_radius", (radius + RING_OUTSET) / (reach * 2.0))
	_glow_material.set_shader_parameter("core_width", 0.02 / (reach * 2.0))
	_glow_material.set_shader_parameter("spill_width", 0.045 / (reach * 2.0))
	_glow_material.set_shader_parameter("intensity", 0.0)
	var glow := MeshInstance3D.new()
	glow.name = "RingGlow"
	glow.mesh = quad
	glow.material_override = _glow_material
	glow.position = Vector3(0, RING_HEIGHT + 0.02, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)

func _build_imprint() -> void:
	_viewport = SubViewport.new(); _viewport.name = "Imprint"
	_viewport.size = Vector2i(IMPRINT_SIZE, IMPRINT_SIZE)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_label = Label.new()
	_label.size = Vector2(IMPRINT_SIZE * TEXT_WIDTH, IMPRINT_SIZE * TEXT_HEIGHT)
	_label.position = Vector2(IMPRINT_SIZE * (1.0 - TEXT_WIDTH) * 0.5, IMPRINT_SIZE * (1.0 - TEXT_HEIGHT) * 0.5)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if imprint_font != null:
		_label.add_theme_font_override("font", imprint_font)
	_label.add_theme_font_size_override("font_size", IMPRINT_FONT_SIZE)
	_label.visible = false
	_viewport.add_child(_label)
	_symbol = Node2D.new()
	_viewport.add_child(_symbol)
	var s := float(IMPRINT_SIZE)
	var c := Vector2(s, s) * 0.5
	if glyph == "play":
		var tri := Polygon2D.new()
		tri.polygon = PackedVector2Array([c + Vector2(s * 0.22, 0), c + Vector2(-s * 0.15, -s * 0.24),
			c + Vector2(-s * 0.15, s * 0.24)])
		_symbol.add_child(tri)
	else:
		for angle in [45.0, -45.0]:
			var bar := Polygon2D.new()
			var half := Vector2(s * 0.27, s * 0.055)
			bar.polygon = PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
			bar.position = c
			bar.rotation = deg_to_rad(angle)
			_symbol.add_child(bar)

func _apply_colors() -> void:
	if _gem_material == null:
		return
	_gem_material.set_shader_parameter("base_color", gem_color.linear_to_srgb())
	_gem_material.set_shader_parameter("emission_color", gem_emission.linear_to_srgb())
	_gem_material.set_shader_parameter("emission_energy", gem_energy)
	_stone_material.set_shader_parameter("base_color", stone_color.linear_to_srgb())
	_stone_material.set_shader_parameter("groove_color", groove_color.linear_to_srgb())
	_glow_material.set_shader_parameter("glow_color", glow_color.linear_to_srgb())

func _add_mesh(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(mi)
	return mi
