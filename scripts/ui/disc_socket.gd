extends Node3D
## One board button sitting in a well of a button station (the housing is baked into the board; see
## Blender/build_button_housing.py). The button is a LENS — two shallow domes joined at a thin metal bezel — on an axle
## along local X. The +Y dome is the gem, with the label or a symbol IMPRINTED in white (shaders/disc_face.gdshader);
## the -Y dome is carved stone. It fills its well, so its rim tucks under the station's iron ring: no gap.
##
## A button is never hidden. It TURNS, and always FORWARD (rotation only ever increases): gem-up when offered, stone-up
## when not. A press FLICKS it (see PRESS_SPIN_*): it spins down to the stone, holds, and only then follows its claims.
##
## The disc is SHARED. Several logical buttons may claim it (Confirm and Pass both use the large one); it shows its gem
## while ANY claimant wants it. Claims are COALESCED to the end of the frame: Assistant routinely hides and re-shows a
## button within one frame (show_modal() hides everything first), and turning on each call would make it twitch.
##
## Hover lights the ring around the button (an additive annulus over the baked iron ring, shaders/disc_ring_glow);
## a press flashes it.

const HALF_TURN_SECONDS := 0.42
const FULL_TURN_SECONDS := 0.7
## A PRESS IS A FLICK. The disc leaves at PRESS_SPIN_SPEED (turns per second) and decelerates at a CONSTANT rate to a
## dead stop on the STONE face, after at least PRESS_SPIN_MIN_TURNS. The deceleration is solved for the stop: the
## stone angle at or past the minimum is the distance d, so a = w0^2 / 2d and the spin lasts T = 2d / w0 (a quadratic
## ease-out is exactly this motion: its starting slope is 2d/T = w0). It then holds still PRESS_HOLD_SECONDS, and the
## disc is LOCKED for the whole spin + hold: claims that change meanwhile wait, presses are refused, and on release it
## turns (plain half turn) to whatever is wanted by then. A state change with no press keeps the plain half/full turn.
const PRESS_SPIN_SPEED := 6.0
const PRESS_SPIN_MIN_TURNS := 2.5
const PRESS_HOLD_SECONDS := 0.5
## The gem's text/symbol is blank while the disc spins; it comes back for the final full turn, so it reads only as the
## disc slows into its stop — and only if the button will be offered again (wants_active()). A press whose button
## stays taken away (no priority) keeps the gem blank for the whole spin.
const IMPRINT_RETURN_ANGLE := TAU
## EVERY turn ends with a little overshoot that rings out: the disc reaches its face still moving at the speed that
## carries it SETTLE_OVERSHOOT radians past (~10 deg), then a damped spring (period SETTLE_PERIOD, decay
## SETTLE_DAMPING per second) brings it back over SETTLE_SECONDS. The main motion is shaped to arrive at exactly that
## speed, so there is no seam between the two.
const SETTLE_OVERSHOOT := 0.18
const SETTLE_PERIOD := 0.22
const SETTLE_DAMPING := 11.0
const SETTLE_SECONDS := 0.45
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
const PILLAR_SHADER := preload("res://shaders/disc_light_pillar.gdshader")
## Light thrown UP off the ring on hover/press: an open cylinder this tall standing on the ring.
const PILLAR_HEIGHT := 0.38
## While the ring's light is ON (hover/press), a few slow motes of light rise off it, as bright as the ring.
const MOTE_AMOUNT := 9
const MOTE_LIFETIME := 2.6
const MOTE_SIZE := 0.03
## The ring intensity above which motes are emitted.
const MOTE_THRESHOLD := 0.3

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
var _imprint_hidden := false        # blanked for the fast part of a press spin
var _busy := false                    # a press spin (or its hold) is playing: nothing else may turn the disc

## The press spin and its hold are over: the disc follows its claims again and may be pressed.
signal released

var _pivot: Node3D
var _gem_material: ShaderMaterial
var _stone_material: ShaderMaterial
var _bezel_material: StandardMaterial3D
var _glow_material: ShaderMaterial
var _pillar_material: ShaderMaterial
var _motes: CPUParticles3D
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

## True while a press spin (or the hold after it) is playing.
func is_busy() -> bool:
	return _busy

## How long a press spin starting at `from` lasts until it has settled on the stone (the hold comes after).
static func press_spin_seconds(from: float = 0.0) -> float:
	var stop := _stone_angle_past(from + PRESS_SPIN_MIN_TURNS * TAU)
	return 2.0 * (stop - from) / (PRESS_SPIN_SPEED * TAU + _settle_speed()) + SETTLE_SECONDS

## A press: the ring flashes and the button spins (started at the end of the frame). Refused while a spin is playing.
func pulse() -> void:
	if _busy:
		return
	_spin_pending = true
	if _glow_material != null:
		_set_glow(PRESS_GLOW)
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
	if _busy:
		return            # the spin finishes first; _release() applies whatever is wanted then
	var target := wants_active()
	if _spin_pending:
		_spin_pending = false
		_start_press_spin()
		return
	_refresh_imprint(target)
	var goal := _goal
	if target != _active:
		goal = _next_angle(_goal, target)
	_active = target
	if is_equal_approx(goal, _goal):
		return
	var from := _pivot.rotation.x
	_goal = goal
	# Text only on a gem that is coming UP; a gem going face down (no priority) goes blank at once.
	_set_imprint_shown(target)
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	var seconds := FULL_TURN_SECONDS if goal - from > PI * 1.5 else HALF_TURN_SECONDS
	_turn_tween = create_tween()
	_turn_tween.tween_method(_pose_turn.bind(from, goal, seconds), 0.0, seconds + SETTLE_SECONDS, seconds + SETTLE_SECONDS)
	_turn_tween.tween_callback(_normalise)

## A plain turn: eases in from rest and arrives at `goal` at the settle speed (a cubic Hermite with zero start slope
## and the arrival slope as its end slope), then the settle.
func _pose_turn(t: float, from: float, goal: float, seconds: float) -> void:
	if t >= seconds:
		_pivot.rotation.x = _settle_angle(goal, t - seconds)
		return
	var d := goal - from
	var x := t / seconds
	var s := _settle_speed() * seconds / d
	_pivot.rotation.x = from + d * ((3.0 * x * x - 2.0 * x * x * x) + s * (x * x * x - x * x))

## Constant deceleration from PRESS_SPIN_SPEED to the settle speed on the stone, the settle, the hold, then release.
func _start_press_spin() -> void:
	_busy = true
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	var from := _pivot.rotation.x
	_goal = _stone_angle_past(from + PRESS_SPIN_MIN_TURNS * TAU)
	_active = false
	_set_imprint_shown(false)
	var total := press_spin_seconds(from)
	_turn_tween = create_tween()
	_turn_tween.tween_method(_pose_press.bind(from, _goal), 0.0, total, total)
	_turn_tween.tween_callback(_normalise)
	_turn_tween.tween_interval(PRESS_HOLD_SECONDS)
	_turn_tween.tween_callback(_release)

func _pose_press(t: float, from: float, goal: float) -> void:
	var w0 := PRESS_SPIN_SPEED * TAU
	var v := _settle_speed()
	var reach := 2.0 * (goal - from) / (w0 + v)       # time to the face
	if t >= reach:
		_pivot.rotation.x = _settle_angle(goal, t - reach)
		return
	var a := (w0 - v) / reach
	_pivot.rotation.x = from + w0 * t - 0.5 * a * t * t

## The settle after arriving at `goal`: a damped sine whose starting speed is the arrival speed.
static func _settle_angle(goal: float, t: float) -> float:
	var wd := TAU / SETTLE_PERIOD
	return goal + _settle_speed() / wd * exp(-SETTLE_DAMPING * t) * sin(wd * t)

## The arrival speed that peaks SETTLE_OVERSHOOT past the face (the first peak of the damped sine is a quarter period in).
static func _settle_speed() -> float:
	var wd := TAU / SETTLE_PERIOD
	return SETTLE_OVERSHOOT * wd * exp(SETTLE_DAMPING * SETTLE_PERIOD * 0.25)

func _process(_delta: float) -> void:
	if _motes != null:
		var want := glow_intensity() > MOTE_THRESHOLD
		if _motes.emitting != want:
			_motes.emitting = want
	if _busy and _imprint_hidden and _goal - _pivot.rotation.x <= IMPRINT_RETURN_ANGLE and wants_active():
		_set_imprint_shown(true)

func _set_imprint_shown(on: bool) -> void:
	_imprint_hidden = not on
	if _gem_material != null:
		_gem_material.set_shader_parameter("use_imprint", on)

## True when the gem currently carries its text or symbol (false during the fast part of a press spin, and through a
## whole press spin whose button is not wanted back).
func imprint_shown() -> bool:
	return not _imprint_hidden

func _release() -> void:
	_busy = false
	released.emit()
	_mark_dirty()

## The first stone-up angle (an odd multiple of PI) at or beyond `from`.
static func _stone_angle_past(from: float) -> float:
	var k := int(ceil(from / PI - 1e-4))
	if k % 2 == 0:
		k += 1
	return k * PI

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
	_glow_tween.tween_method(_set_glow, glow_intensity(), value, seconds)

## The ring and the pillar above it share one intensity.
func _set_glow(v: float) -> void:
	_glow_material.set_shader_parameter("intensity", v)
	if _pillar_material != null:
		_pillar_material.set_shader_parameter("intensity", v)
	_tint_motes()

## Motes are the ring's own light: its colour, at its brightness (the ring's core is drawn at 0.9 * intensity).
func _tint_motes() -> void:
	if _motes == null:
		return
	var c := glow_color.linear_to_srgb()
	c.a = clampf(glow_intensity() * 0.9, 0.0, 1.0)
	_motes.color = c

func glow_intensity() -> float:
	var v = _glow_material.get_shader_parameter("intensity") if _glow_material != null else null
	return float(v) if v is float else 0.0

## True while the motes are rising (the ring's light is on).
func motes_emitting() -> bool:
	return _motes != null and _motes.emitting


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
	_build_pillar()
	_build_motes()

## An open cylinder of light standing on the ring (no caps: a cap would be a lit disc over the button).
func _build_pillar() -> void:
	var tube := CylinderMesh.new()
	tube.top_radius = radius + RING_OUTSET
	tube.bottom_radius = radius + RING_OUTSET
	tube.height = PILLAR_HEIGHT
	tube.radial_segments = 64
	tube.rings = 8
	tube.cap_top = false
	tube.cap_bottom = false
	_pillar_material = ShaderMaterial.new(); _pillar_material.shader = PILLAR_SHADER
	_pillar_material.set_shader_parameter("height", PILLAR_HEIGHT)
	_pillar_material.set_shader_parameter("intensity", 0.0)
	_pillar_material.render_priority = 1
	var pillar := MeshInstance3D.new()
	pillar.name = "LightPillar"
	pillar.mesh = tube
	pillar.material_override = _pillar_material
	pillar.position = Vector3(0, RING_HEIGHT + PILLAR_HEIGHT * 0.5, 0)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pillar)

## Slow motes of light drifting up off the ring while its light is on.
func _build_motes() -> void:
	_motes = CPUParticles3D.new()
	_motes.name = "Motes"
	_motes.emitting = false
	_motes.amount = MOTE_AMOUNT
	_motes.lifetime = MOTE_LIFETIME
	_motes.randomness = 0.6
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_motes.emission_ring_axis = Vector3.UP
	_motes.emission_ring_radius = radius + RING_OUTSET
	_motes.emission_ring_inner_radius = radius + RING_OUTSET - 0.008
	_motes.emission_ring_height = 0.01
	_motes.direction = Vector3.UP
	_motes.spread = 12.0
	_motes.initial_velocity_min = 0.06
	_motes.initial_velocity_max = 0.13
	_motes.gravity = Vector3(0, 0.015, 0)
	_motes.damping_min = 0.01
	_motes.damping_max = 0.03
	_motes.scale_amount_min = 0.5
	_motes.scale_amount_max = 1.1
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	_motes.color_ramp = fade
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 64; dot.height = 64
	var soft := Gradient.new()
	soft.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	soft.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	dot.gradient = soft
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = dot
	mat.render_priority = 2
	var quad := QuadMesh.new()
	quad.size = Vector2(MOTE_SIZE, MOTE_SIZE)
	quad.material = mat
	_motes.mesh = quad
	_motes.position = Vector3(0, RING_HEIGHT + 0.01, 0)
	add_child(_motes)

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
	_pillar_material.set_shader_parameter("glow_color", glow_color.linear_to_srgb())
	_tint_motes()

func _add_mesh(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(mi)
	return mi
