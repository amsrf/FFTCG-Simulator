extends RefCounted
## TELEPORT CAST presentation for one card: the source shines in place and dissolves, the destination builds a
## glowing silhouette from the bottom up and then reveals its art. Pure presentation — it never moves the card or
## touches game state. Owned by Card as `card.teleport`.
##
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the global cache, which is
## a parse error on every headless run.

## Additive halo around the card during the teleport. Created lazily and only shown while the glow is non-zero.
const HALO_SHADER := preload("res://shaders/card_teleport_halo.gdshader")
const HALO_SCALE := 1.55

## Card is a Node3D; kept untyped so this file and card.gd do not depend on each other's class_name.
var _card: Node3D
## The current presentation tween (source fade or destination materialise).
var tween: Tween
var halo: MeshInstance3D = null
var _halo_material: ShaderMaterial = null
## The card's border surface and power label are not part of the materialising face. Hide them until the texture is
## fully revealed, then restore the label's previous visibility.
var chrome_hidden: bool = false
var _power_was_visible: bool = false
var _hidden_material: ShaderMaterial = null

func _init(card: Node3D) -> void:
	_card = card

## Source half: shine in place, then dissolve away. The card does not move. Returns the tween so the caller can
## await it.
func play_out(shine_seconds: float = 0.45, fade_seconds: float = 0.20) -> Tween:
	_kill_tween()
	# The source must stay where it is. Either row could still be settling (Characters fade from the hand, Summons
	# from the Stack), so stop both layout tweens rather than letting the card drift while it shines.
	_card.stop_hand_layout()
	_card.stop_stack_layout()
	_card.visible = true
	set_visual(0.0, 0.0)
	var t := _card.create_tween()
	# Reveal stays 0 so the card itself turns into a white silhouette as the glow rises. allow_halo=false: the
	# source glows INSIDE the card and then fades, it does not grow a halo.
	t.tween_method(func(v: float): set_visual(0.0, v, 0.0, false), 0.0, 1.0, maxf(shine_seconds, 0.01))
	t.tween_method(func(v: float): set_visual(v, 1.0 - 0.35 * v, 0.0, false), 0.0, 1.0, maxf(fade_seconds, 0.01))
	t.tween_callback(func():
		set_visual(1.0, 0.0)
		_card.visible = false)
	tween = t
	return t

## Destination half: build the glowing silhouette from the bottom up, brighten it once complete, then fade the glow
## while revealing the actual artwork.
func play_in(build_seconds: float = 0.65, glow_seconds: float = 0.18, reveal_seconds: float = 0.30) -> Tween:
	_kill_tween()
	_card.visible = true
	set_visual(1.0, 0.35, 0.0)
	var t := _card.create_tween()
	# 1. Add the glow squares from bottom to top. Reveal stays 0: the texture is never visible while the silhouette
	#    is incomplete.
	t.tween_method(func(v: float): set_visual(1.0 - v, 0.35 + 0.45 * v, 0.0), 0.0, 1.0, maxf(build_seconds, 0.01))
	# 2. The completed silhouette brightens.
	t.tween_method(func(v: float): set_visual(0.0, 0.80 + 0.20 * v, 0.0), 0.0, 1.0, maxf(glow_seconds, 0.01))
	# 3. The glow fades away as the card texture is revealed.
	t.tween_method(func(v: float): set_visual(0.0, 1.0 - v, v), 0.0, 1.0, maxf(reveal_seconds, 0.01))
	t.tween_callback(func(): set_visual(0.0, 0.0, 1.0))
	tween = t
	return t

func set_visual(progress: float, glow: float, reveal: float = 1.0, allow_halo: bool = true) -> void:
	var mat: ShaderMaterial = _card.mat
	if mat == null:
		return
	mat.set_shader_parameter("teleport_progress", clampf(progress, 0.0, 1.0))
	mat.set_shader_parameter("teleport_glow", clampf(glow, 0.0, 1.0))
	mat.set_shader_parameter("teleport_reveal", clampf(reveal, 0.0, 1.0))
	# The border and power readout are not part of the glow silhouette. They appear only after the texture is fully
	# revealed.
	_set_chrome_hidden(reveal < 0.999)
	# The halo belongs only to the DESTINATION's completed silhouette. The source passes allow_halo=false for both its
	# shine and fade, so the card brightens inside its own rectangle and never grows an overflow outline.
	var halo_on: bool = allow_halo and glow > 0.001 and progress <= 0.001
	if halo_on:
		_ensure_halo()
	if halo != null:
		halo.visible = halo_on
		if _halo_material != null:
			_halo_material.set_shader_parameter("intensity", clampf(glow * 1.25, 0.0, 1.5))

## Back to a plain, fully revealed card. Called on every zone change.
func reset() -> void:
	_kill_tween()
	set_visual(0.0, 0.0, 1.0)

func _set_chrome_hidden(hidden: bool) -> void:
	if hidden == chrome_hidden:
		return
	chrome_hidden = hidden
	if _hidden_material == null:
		var shader := Shader.new()
		shader.code = "shader_type spatial;
render_mode unshaded;
void fragment() { discard; }
"
		_hidden_material = ShaderMaterial.new()
		_hidden_material.shader = shader
	for mesh in [_card.get_node_or_null("HandMesh"), _card.get_node_or_null("FieldMesh")]:
		if mesh is MeshInstance3D:
			# Surface 0 is the face; 1 is the printed border; 2 is the back. Hide both non-face surfaces or the card
			# still reads as a full rectangle before the build has produced anything.
			for surface in [1, 2]:
				mesh.set_surface_override_material(surface, _hidden_material if hidden else null)
	var power_label = _card.power_label
	if hidden:
		_power_was_visible = power_label != null and power_label.visible
		if power_label != null:
			power_label.visible = false
	elif power_label != null and _power_was_visible:
		power_label.visible = true
	_power_was_visible = false

func _ensure_halo() -> void:
	if halo != null and is_instance_valid(halo):
		return
	var face: Vector2 = _card._card_face_size()
	var quad := PlaneMesh.new()
	quad.size = face * HALO_SCALE
	_halo_material = ShaderMaterial.new()
	_halo_material.shader = HALO_SHADER
	var half: float = 1.0 / HALO_SCALE
	_halo_material.set_shader_parameter("card_half", Vector2(half, half))
	halo = MeshInstance3D.new()
	halo.mesh = quad
	halo.material_override = _halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.extra_cull_margin = 4.0
	halo.position = Vector3(0.0, 0.004, 0.0)
	halo.visible = false
	_card.add_child(halo)

func _kill_tween() -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	tween = null
