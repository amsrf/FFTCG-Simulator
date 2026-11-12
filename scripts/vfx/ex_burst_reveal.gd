extends Node3D
## EX BURST REVEAL: the drama on a damage card that carries an EX BURST, while the damage camera looks at it. After
## Clips/damage_trigger frames 194+. Started by Game.stage_ex_burst_reveal() as the card leaves the deck; everything
## waits `delay` (the card's flight into the Damage Zone) and then, as it lands:
##   * a gold AURA snaps onto the card's outline (a light running round it) and stays while the title is up
##   * two PULSES leave the outline and expand outward as they fade
##   * a light STREAK shoots across the screen and the title "EX BURST" rides in on it (italic, gold gradient, dark
##     outline), punches, a shine sweeps across it, it holds, then everything fades
## Driven by its own clock in _process, so freezing time (Engine.time_scale = 0) freezes a frame for screenshots.
## Frees itself (and the aura it put on the card) when done.

const AURA_SHADER := preload("res://shaders/ex_burst_aura.gdshader")
const TITLE_SHADER := preload("res://shaders/ex_burst_title.gdshader")
const STREAK_SHADER := preload("res://shaders/ex_burst_streak.gdshader")
const FONT := preload("res://assets/fonts/FOT-NewRodin Pro EB.otf")

## From the landing to the end of the fade. PlayerSide.EX_BURST_DELAY and the damage zoom's hold are derived from it.
const SECONDS := 1.8
const FADE := 0.30
const TITLE_IN := 0.24
const STREAK_IN := 0.30
const PULSE_SECONDS := 0.55
const PULSE_GAP := 0.22
const PULSE_REACH := 0.20   # card-face units beyond the outline
## The aura quad reaches this far beyond the card on every side (must hold the pulses' reach).
const MARGIN := 0.26
const TITLE := "EX BURST"
const TITLE_SKEW := -0.28
## Title size and place, as fractions of the viewport height / size.
const TITLE_HEIGHT := 0.12
const TITLE_Y := 0.85

var _card: Card = null
var _delay := 0.0
var _age := 0.0
var _aura: MeshInstance3D = null
var _aura_mat: ShaderMaterial = null
var _layer: CanvasLayer = null
var _title_root: Node2D = null
var _title: Label = null
var _title_mat: ShaderMaterial = null
var _streak: ColorRect = null
var _streak_mat: ShaderMaterial = null
var _title_home := Vector2.ZERO


## `card` is the damage card, `delay` how long until it lands.
func setup(card: Card, delay: float) -> void:
	_card = card
	_delay = delay
	_build()
	_sample(0.0)


func _process(delta: float) -> void:
	_age += delta
	if not is_instance_valid(_card):
		queue_free()
		return
	_sample(_age)
	if _age >= _delay + SECONDS:
		queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_aura):
		_aura.queue_free()


func _build() -> void:
	var face: Vector2 = _card._card_face_size()
	var quad := PlaneMesh.new()
	quad.size = face + Vector2.ONE * MARGIN * 2.0
	_aura_mat = ShaderMaterial.new()
	_aura_mat.shader = AURA_SHADER
	_aura_mat.render_priority = 4
	_aura_mat.set_shader_parameter("card_size", face)
	_aura = MeshInstance3D.new()
	_aura.name = "ExBurstAura"
	_aura.mesh = quad
	_aura.material_override = _aura_mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.extra_cull_margin = 2.0
	_aura.position = Vector3(0.0, 0.004, 0.0)
	# On the visible mesh, like the target ring: it follows the card wherever the zone lays it out.
	var host: Node3D = _card.hand_mesh if _card.hand_mesh != null else _card
	host.add_child(_aura)

	_layer = CanvasLayer.new()
	_layer.layer = 60
	add_child(_layer)
	var view: Vector2 = get_viewport().get_visible_rect().size
	_streak_mat = ShaderMaterial.new()
	_streak_mat.shader = STREAK_SHADER
	_streak = ColorRect.new()
	_streak.name = "ExBurstStreak"
	_streak.material = _streak_mat
	_streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak.size = Vector2(view.x * 1.1, view.y * 0.05)
	_streak.position = Vector2(-view.x * 0.05, view.y * (TITLE_Y + TITLE_HEIGHT * 0.36) - _streak.size.y * 0.5)
	_layer.add_child(_streak)

	_title_root = Node2D.new()
	_title_root.name = "ExBurstTitle"
	_title_root.skew = TITLE_SKEW
	_layer.add_child(_title_root)
	_title = Label.new()
	_title.text = TITLE
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var size_px: int = int(round(view.y * TITLE_HEIGHT))
	_title.add_theme_font_override("font", FONT)
	_title.add_theme_font_size_override("font_size", size_px)
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", maxi(4, size_px / 9))
	_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	_title.add_theme_constant_override("shadow_offset_x", maxi(2, size_px / 28))
	_title.add_theme_constant_override("shadow_offset_y", maxi(2, size_px / 22))
	_title_mat = ShaderMaterial.new()
	_title_mat.shader = TITLE_SHADER
	_title.material = _title_mat
	_title_root.add_child(_title)
	var text_size: Vector2 = FONT.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	_title.size = text_size
	_title.position = -text_size * 0.5
	_title_mat.set_shader_parameter("label_size", text_size)
	_title_home = Vector2(view.x * 0.5, view.y * TITLE_Y)
	_title_root.position = _title_home


## Everything at `t` seconds after setup.
func _sample(t: float) -> void:
	var s := t - _delay   # time since the card landed
	var live := s >= 0.0
	_aura.visible = live
	_layer.visible = live
	if not live:
		return
	var out := 1.0 - smoothstep(SECONDS - FADE, SECONDS, s)
	# Aura: snaps on brighter than it rests, then settles; fades with the rest.
	var flare := 1.0 + 0.9 * exp(-s * 9.0)
	_aura_mat.set_shader_parameter("intensity", smoothstep(0.0, 0.06, s) * flare * out)
	for pulse in [["pulse_a", 0.0], ["pulse_b", PULSE_GAP]]:
		var p := clampf((s - float(pulse[1])) / PULSE_SECONDS, 0.0, 1.0)
		var on := s >= float(pulse[1]) and p < 1.0
		_aura_mat.set_shader_parameter(pulse[0], (1.0 - pow(1.0 - p, 2.5)) * PULSE_REACH)
		_aura_mat.set_shader_parameter(pulse[0] + "_alpha", (1.0 - p) * 1.4 if on else 0.0)
	# Streak: shoots across, then dims to a faint line and goes with the title.
	var streak_p := clampf(s / STREAK_IN, 0.0, 1.0)
	_streak_mat.set_shader_parameter("reveal", 1.0 - pow(1.0 - streak_p, 3.0))
	_streak_mat.set_shader_parameter("intensity", (0.45 + 0.75 * exp(-maxf(s - STREAK_IN, 0.0) * 4.0)) * out)
	# Title: slides in from the left on the streak's head, overshoots in scale, settles; a shine passes across it.
	var view_w: float = get_viewport().get_visible_rect().size.x
	var a := clampf((s - 0.04) / TITLE_IN, 0.0, 1.0)
	var slide := 1.0 - pow(1.0 - a, 3.0)
	_title_root.position = _title_home + Vector2(-view_w * 0.35 * (1.0 - slide), 0.0)
	var punch := 1.0 + 0.18 * exp(-maxf(s - 0.04 - TITLE_IN, 0.0) * 10.0) * a
	_title_root.scale = Vector2.ONE * punch
	_title_root.modulate.a = smoothstep(0.0, 0.5, a) * out
	_title_mat.set_shader_parameter("shine", lerpf(-0.3, 1.3, clampf((s - 0.38) / 0.45, 0.0, 1.0)))
