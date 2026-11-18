extends RefCounted
## DAMAGE PRESENTATION for one card: the quick recoil on effect damage, and the Earth launch (the card is thrown up
## by a totem and lands back in its slot). Pure presentation — the damage itself is Card.suffer_damage(). Owned by
## Card as `card.damage_fx`.
##
## Both animate the HandMesh rather than the Card root: the Card's transform belongs to the field layout, so animating
## it would fight the board. They share one tween and one "rest pose", which is why they live together.
##
## Preloaded by PATH (no class_name): a class_name added since Godot last scanned is not in the global cache, which is
## a parse error on every headless run.

## RECOIL: the card SNAPS up and tips toward the camera about its near edge (a little jump), then RETURNS SLOWLY on a
## weakly damped spring: it sinks back over ~0.3 s, the tip swings past flat onto the other edge and back a few times,
## each swing smaller, and it comes to rest after 1.4-2.1 s. There is no snap back: the spring is faded to
## exactly zero before the pose is reset. The lift never goes below the board (the card rests on it while the tip
## rocks), and a tip either way pivots on the edge that stays down, so no corner enters the board.
##   SHADING   the face brightens as it turns toward the light (camera side), and flickers as it rocks
##             (card.gdshader `face_light`);
##   SHADOW    a soft board shadow that grows with height.
## Every hit is ROLLED (roll_reaction): each size and timing below is a base that the roll varies within its range,
## so two hits never look the same but always look like the same kind of hit.
## The snap: seconds from rest to the full jump.
const REACTION_RISE := 0.04
## The return spring: one full swing takes this long (slow), and its amplitude falls by e every 1/damping seconds
## (weak: after one swing about a third is left).
const SPRING_PERIOD := 0.85
const SPRING_DAMPING := 2.4
## The spring is cut when its envelope is this small, faded to zero over the last REACTION_FADE seconds.
const SPRING_CUTOFF := 0.02
const REACTION_FADE := 0.15
## Sizes, by damage tier: a LITTLE jump. The tip stays near 20 deg: on this ~67 deg board camera a flat card is already
## 23 deg from facing it, so more tip makes the card look SHORTER, not tipped (measured; see AGENTS.md).
const REACTION_LIFT := [0.16, 0.19, 0.22, 0.25]
const REACTION_PITCH_DEG := [18.0, 20.0, 22.0, 24.0]
const REACTION_YAW_DEG := [3.0, 3.5, 4.0, 4.5]
## Roll ranges (multipliers unless noted).
const VARY_LIFT := Vector2(0.85, 1.15)
const VARY_PITCH_DEG := Vector2(-3.0, 3.0)
const VARY_YAW := Vector2(0.6, 1.4)
## Most hits turn left, a few right.
const YAW_LEFT_CHANCE := 0.7
const VARY_PERIOD := Vector2(0.85, 1.15)
const VARY_DAMPING := Vector2(0.8, 1.2)
## Half the card face in its local units (Card._card_face_size() / 2).
const HALF_FACE := Vector2(0.2145, 0.3)
## Shading: the light sits above, on the camera side and a little to the right; FACE_LIGHT_GAIN turns the change in
## dot(normal, light) into the shader's -1..1 `face_light` (20 deg of tip -> ~+0.15).
const LIGHT_DIR := Vector3(0.35, 0.6, 0.7)
const FACE_LIGHT_GAIN := 0.75
const FACE_LIGHT_LIMIT := 0.3
## The board shadow.
const SHADOW_STRENGTH := 0.65
const SHADOW_SOFTNESS := Vector2(0.012, 0.05)
const SHADOW_MARGIN := 0.12
const SHADOW_DEPTH := 0.002
## Per metre of height: screen-left and toward the camera, so it shows beside the card instead of under it.
const SHADOW_FALL := Vector2(-0.25, 0.45)
const SHADOW_SHADER := preload("res://shaders/card_lift_shadow.gdshader")
## Card children drawn ON the face that are not HandMesh children; they ride with the pose. (Plus the power readout.)
const CHROME_NODES: Array[String] = ["CardEdge", "CostBadge"]

## Earth launch follows gravity and returns exactly to the mesh's resting pose.
const EARTH_LAUNCH_HEIGHTS: Array[float] = [1.0, 1.6, 2.2, 2.9]
const EARTH_LAUNCH_GRAVITY := 9.8
## Whole PITCH turns the thrown card makes in the air, per damage tier. Whole turns, with the spin dying out toward
## touchdown, so it comes down flat on its slot and needs no correction on landing.
const EARTH_LAUNCH_TURNS: Array[int] = [1, 1, 2, 2]
signal earth_landed

## Card is a Node3D; kept untyped so this file and card.gd do not depend on each other's class_name.
var _card: Node3D
## The running recoil OR launch tween. Starting either one stops the other.
var tween: Tween = null
## When the falling card first touches the board, measured from the start of the launch (after any delay).
var earth_contact_seconds := 0.0

## This hit's roll (roll_reaction): sizes, timings and directions; see reaction_pose() for the keys.
var _params: Dictionary = {}
var _far_sign := 1.0
## How far the card is turned from upright about its up axis when the hit starts (radians): its DULL TILT. The hit
## undoes it, so a dulled card is shown STRAIGHT while it is knocked loose and dulled again once it settles.
var _untilt := 0.0
## Presentation-only randomness; never Game.rng, which is reserved for rules.
var _rng := RandomNumberGenerator.new()
var _shadow: MeshInstance3D = null
var _shadow_mat: ShaderMaterial = null
var _chrome_active := false
var _chrome_homes: Dictionary = {}
var _power_home := Transform3D.IDENTITY
var _power_was_visible := false
var _power_hidden := false

func _init(card: Node3D) -> void:
	_card = card
	_rng.randomize()

func is_reacting() -> bool:
	return tween != null and tween.is_valid() and tween.is_running()

## Stop whatever is running and put the mesh back at rest. Called on every zone change.
func normalize() -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	tween = null
	_reset_pose()

## Quick physical recoil on the visible mesh.
func play_reaction(damage: int, delay: float = 0.0) -> void:
	var hand_mesh = _card.hand_mesh
	if damage <= 0 or hand_mesh == null or not _card.is_drawn_on_field():
		return
	var tier: int = VfxEvent.damage_tier_for(damage)
	normalize()
	_params = roll_reaction(tier, _rng.randi())
	_far_sign = _toward_camera_sign()
	_untilt = wrapf(deg_to_rad(_card.rotation_degrees.y - float(_card.get("_upright_y"))), -PI, PI)
	var seconds: float = _params.end
	var t := _card.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_callback(func() -> void: _capture_chrome(false))
	t.tween_method(_set_reaction_pose, 0.0, seconds, seconds)
	t.tween_callback(_finish)
	tween = t

func earth_launch_seconds(damage: int) -> float:
	return sqrt(8.0 * EARTH_LAUNCH_HEIGHTS[VfxEvent.damage_tier_for(damage)] / EARTH_LAUNCH_GRAVITY)

func play_earth_launch(damage: int, seed_value: int = 1, delay: float = 0.0) -> Tween:
	var hand_mesh = _card.hand_mesh
	if hand_mesh == null or not _card.is_drawn_on_field():
		return null
	normalize()
	var duration := earth_launch_seconds(damage)
	var velocity := EARTH_LAUNCH_GRAVITY * duration * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# The card flips end over end (pitch) a whole number of times; a small bounded wavering rides on top. Both fade
	# away before touchdown, preserving the planned landing pose.
	var turns := float(EARTH_LAUNCH_TURNS[VfxEvent.damage_tier_for(damage)]) * (1.0 if rng.randf() < 0.5 else -1.0)
	var frequencies := Vector3(rng.randf_range(5.0, 7.0), rng.randf_range(3.0, 5.0), rng.randf_range(4.0, 6.0))
	var phases := Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
	var excursion := Vector3(rng.randf_range(-0.045, 0.045), 0.0, rng.randf_range(-0.035, 0.035))
	var landing_offset := Vector3(rng.randf_range(-0.006, 0.006), 0.0, rng.randf_range(-0.006, 0.006))
	var landing_tilt := Vector3(rng.randf_range(-0.015, 0.015), rng.randf_range(-0.020, 0.020), rng.randf_range(-0.015, 0.015))
	var card := _card
	var pose_at := func(time: float) -> Transform3D:
		var p := clampf(time / duration, 0.0, 1.0)
		var height := velocity * time - 0.5 * EARTH_LAUNCH_GRAVITY * time * time
		var lateral := excursion * pow(sin(PI * p), 2.0) + landing_offset * smoothstep(0.45, 0.94, p)
		var position_local: Vector3 = card.global_basis.inverse() * (Vector3.UP * height + lateral)
		var envelope := pow(sin(PI * p), 2.0)
		var angles := Vector3(
			sin(time * frequencies.x + phases.x) * deg_to_rad(7.5),
			sin(time * frequencies.y + phases.y) * deg_to_rad(3.0),
			sin(time * frequencies.z + phases.z) * deg_to_rad(6.0)) * envelope
		angles += landing_tilt * smoothstep(0.65, 0.94, p)
		# Spin speed follows 1 - cos: nothing at the launch, fastest at the top of the arc, nothing again at the
		# landing - so the last stretch of the fall is the card arriving flat, not a rotation being stopped.
		var spin := TAU * turns * (p - sin(TAU * p) / TAU)
		var orientation := Basis(Vector3.RIGHT, spin) * Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.UP, angles.y) \
			* Basis(Vector3.BACK, angles.z)
		return Transform3D(orientation, position_local)
	# First corner contact ends the free fall. The centre need not reach zero:
	# a tilted card touches the ground earlier than a flat one.
	var resting_bottom := _earth_lowest_offset(Transform3D.IDENTITY)
	var low := duration * 0.5
	var high := duration + 0.2
	for i in range(1, 81):
		var sample_time := lerpf(duration * 0.5, duration + 0.2, float(i) / 80.0)
		if _earth_lowest_offset(pose_at.call(sample_time)) <= resting_bottom:
			high = sample_time
			break
		low = sample_time
	for _iteration in range(18):
		var middle := (low + high) * 0.5
		if _earth_lowest_offset(pose_at.call(middle)) > resting_bottom:
			low = middle
		else:
			high = middle
	earth_contact_seconds = high
	var contact_pose: Transform3D = pose_at.call(earth_contact_seconds)
	_capture_chrome(true)
	var apply_pose := func(pose: Transform3D) -> void:
		if not card.is_drawn_on_field():
			return
		hand_mesh.transform = pose
		_apply_chrome(pose)
	var t := _card.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_method(func(time: float): apply_pose.call(pose_at.call(time)), 0.0, earth_contact_seconds, earth_contact_seconds)
	t.tween_callback(func(): earth_landed.emit())
	# A small damped rebound and short roll/slide bring a survivor back to its
	# slot after contact, instead of steering it upright while still airborne.
	t.tween_method(func(p: float) -> void:
		var settle := 1.0 - pow(1.0 - p, 3.0)
		var pose := contact_pose.interpolate_with(Transform3D.IDENTITY, settle)
		var penetration := resting_bottom - _earth_lowest_offset(pose)
		pose.origin += card.global_basis.inverse() * Vector3.UP * (maxf(0.0, penetration) + sin(PI * p) * 0.012 * (1.0 - p))
		apply_pose.call(pose)
	, 0.0, 1.0, 0.12)
	t.tween_callback(_finish)
	tween = t
	return t

## The lowest corner of the card face, in world Y, for a given HandMesh pose.
func _earth_lowest_offset(pose: Transform3D) -> float:
	var half: Vector2 = _card._card_face_size() * 0.5
	var lowest := INF
	for corner in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]:
		lowest = minf(lowest, (_card.global_basis * (pose * corner)).y)
	return lowest

## +1 when tipping about the card's local X raises its local -Z edge toward the camera (the local player's cards),
## -1 when the far edge is local +Z (the other seat's cards face the other way).
func _toward_camera_sign() -> float:
	var camera := _card.get_viewport().get_camera_3d() if _card.is_inside_tree() else null
	if camera == null:
		return 1.0
	var top: Vector3 = _card.global_basis * Vector3.FORWARD
	var to_camera: Vector3 = camera.global_position - _card.global_position
	top.y = 0.0
	to_camera.y = 0.0
	return -1.0 if top.dot(to_camera) > 0.0 else 1.0

static func _ease_out(u: float) -> float:
	return 1.0 - (1.0 - u) * (1.0 - u)

static func _smoother(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)

## Rolls one hit: every size and timing varied within its range, and the turn's direction. Static and seeded, so a
## probe can sweep many seeds.
static func roll_reaction(tier: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	tier = clampi(tier, 0, REACTION_LIFT.size() - 1)
	var vary := func(range_value: Vector2) -> float: return rng.randf_range(range_value.x, range_value.y)
	var yaw_sign := 1.0 if rng.randf() < YAW_LEFT_CHANCE else -1.0
	var damping: float = SPRING_DAMPING * vary.call(VARY_DAMPING)
	return {
		"rise": REACTION_RISE,
		"period": SPRING_PERIOD * vary.call(VARY_PERIOD),
		"damping": damping,
		"end": REACTION_RISE + log(1.0 / SPRING_CUTOFF) / damping,
		"lift": float(REACTION_LIFT[tier]) * vary.call(VARY_LIFT),
		"pitch": float(REACTION_PITCH_DEG[tier]) + vary.call(VARY_PITCH_DEG),
		"yaw": float(REACTION_YAW_DEG[tier]) * vary.call(VARY_YAW) * yaw_sign,
	}

## The hit's shape at `t`, 1 at the top of the jump: the snap (0 -> 1 in `rise`), then the return spring, released from
## rest at the top so it starts slowly: e^(-d u) (cos w u + d/w sin w u). It goes NEGATIVE (the overshoot) and is faded
## to exactly 0 at `end`.
static func reaction_spring(t: float, p: Dictionary) -> float:
	var rise: float = p.rise
	var end: float = p.end
	if t <= 0.0 or t >= end:
		return 0.0
	if t < rise:
		return _ease_out(t / rise)
	var u: float = t - rise
	var w: float = TAU / float(p.period)
	var d: float = p.damping
	var value: float = exp(-d * u) * (cos(w * u) + d / w * sin(w * u))
	return value * (1.0 - smoothstep(end - REACTION_FADE, end, t))

## STRAIGHTENING A DULLED CARD for the hit: 0 at rest, 1 by the top of the snap, held through the swings, and back to 0
## over the last UNTILT_RETURN seconds, so the card settles dulled again exactly when the spring stops.
const UNTILT_RETURN := 0.35

static func untilt_weight(t: float, p: Dictionary) -> float:
	var end: float = p.end
	if t <= 0.0 or t >= end:
		return 0.0
	return clampf(t / float(p.rise), 0.0, 1.0) * (1.0 - smoothstep(end - UNTILT_RETURN, end, t))

## The HandMesh pose at `t` for the rolled hit `p`, in the CARD'S LOCAL frame (local +Y is world up; field cards are
## turned half a turn about Y, so never convert this through the card's world basis). `scale` divides the world
## metres into local units. LIFT * YAW * TIP. The lift follows only the positive half of the spring (the card rests on
## the board through the overshoot); the tip follows all of it, and pivots on whichever edge stays down: the near edge
## while the far edge rises toward the camera, the far edge while the overshoot lifts the near one.
##
## `untilt` is the card's dull tilt (radians about its up axis); it is turned back out for the hit (untilt_weight), so a
## dulled card is knocked loose STRAIGHT. The card's own up axis is the board's, so this undoes the tap exactly.
static func reaction_pose(t: float, far_sign: float, p: Dictionary, scale: float = 1.0, untilt: float = 0.0) -> Transform3D:
	var s := reaction_spring(t, p)
	var straighten := Transform3D(Basis(Vector3.UP, -untilt * untilt_weight(t, p)), Vector3.ZERO)
	if s == 0.0:
		return straighten
	var pitch_angle := deg_to_rad(float(p.pitch)) * s
	var pitch_basis := Basis(Vector3.RIGHT, pitch_angle * far_sign)
	var pivot := Vector3(0.0, 0.0, HALF_FACE.y * far_sign * signf(s))
	var pitch := Transform3D(pitch_basis, pivot - pitch_basis * pivot)
	# Positive about world up is counter-clockwise seen from the downward-looking camera: the turn to the left.
	var yaw := Transform3D(Basis(Vector3.UP, deg_to_rad(float(p.yaw)) * s), Vector3.ZERO)
	var height := float(p.lift) * maxf(s, 0.0) / scale
	return Transform3D(Basis.IDENTITY, Vector3.UP * height) * straighten * yaw * pitch

func _set_reaction_pose(seconds: float) -> void:
	var hand_mesh = _card.hand_mesh
	if hand_mesh == null or not is_instance_valid(hand_mesh):
		return
	if not _card.is_drawn_on_field() or _params.is_empty():
		_reset_pose()
		return
	var card_scale: float = maxf(_card.global_basis.get_scale().y, 0.0001)
	var pose := reaction_pose(seconds, _far_sign, _params, card_scale, _untilt)
	hand_mesh.transform = pose
	_apply_chrome(pose)
	_set_face_light(face_light_for(pose))
	var tip: float = deg_to_rad(float(_params.pitch))
	var height: float = pose.origin.y * card_scale + HALF_FACE.y * absf(sin(tip * reaction_spring(seconds, _params)))
	_set_shadow(clampf(height / (float(_params.lift) + HALF_FACE.y * sin(tip)), 0.0, 1.0), height)

## Probe hook: this hit's roll.
func reaction_params() -> Dictionary:
	return _params

## How much this pose turns the face toward (+) or away from (-) the light, as the shader's `face_light`. The light
## is fixed relative to the CAMERA (above, on its side, a little to the right), so it reads the same on both seats.
func face_light_for(pose: Transform3D) -> float:
	var camera := _card.get_viewport().get_camera_3d() if _card.is_inside_tree() else null
	if camera == null:
		return 0.0
	var toward: Vector3 = camera.global_position - _card.global_position
	toward.y = 0.0
	var right: Vector3 = camera.global_basis.x
	right.y = 0.0
	var light: Vector3 = (right.normalized() * LIGHT_DIR.x + Vector3.UP * LIGHT_DIR.y + toward.normalized() * LIGHT_DIR.z).normalized()
	var normal: Vector3 = (_card.global_basis * (pose.basis * Vector3.UP)).normalized()
	return clampf((normal.dot(light) - light.y) * FACE_LIGHT_GAIN, -FACE_LIGHT_LIMIT, FACE_LIGHT_LIMIT)

func _set_face_light(value: float) -> void:
	var material = _card.mat
	if material != null:
		material.set_shader_parameter("face_light", value)

## Probe hook: the face_light currently on the card's material.
func face_light() -> float:
	var material = _card.mat
	if material == null:
		return 0.0
	var value = material.get_shader_parameter("face_light")
	return float(value) if value is float else 0.0

func _apply_chrome(pose: Transform3D) -> void:
	if not _chrome_active:
		return
	for node_name in _chrome_homes:
		var node := _card.get_node_or_null(node_name) as Node3D
		if node != null:
			node.transform = pose * (_chrome_homes[node_name] as Transform3D)
	var power_label = _card.power_label
	if power_label != null and not _power_hidden:
		power_label.transform = pose * _power_home

func _capture_chrome(hide_power: bool) -> void:
	if not _chrome_active:
		_chrome_homes.clear()
		for node_name in CHROME_NODES:
			var node := _card.get_node_or_null(node_name) as Node3D
			if node != null:
				_chrome_homes[node_name] = node.transform
		var power_label = _card.power_label
		_power_home = power_label.transform if power_label != null else Transform3D.IDENTITY
		_power_was_visible = power_label.visible if power_label != null else false
		_chrome_active = true
	if hide_power and _card.power_label != null:
		_card.power_label.visible = false
		_power_hidden = true

## `amount` 0..1 of the peak height; `height` in metres pushes the shadow out from under the card.
func _set_shadow(amount: float, height: float) -> void:
	if amount <= 0.0:
		if _shadow != null and is_instance_valid(_shadow):
			_shadow.visible = false
		return
	_ensure_shadow()
	_shadow.visible = true
	var fall := Vector3.ZERO
	var camera := _card.get_viewport().get_camera_3d()
	if camera != null:
		var right: Vector3 = camera.global_basis.x
		right.y = 0.0
		var toward: Vector3 = camera.global_position - _card.global_position
		toward.y = 0.0
		fall = (right.normalized() * SHADOW_FALL.x + toward.normalized() * SHADOW_FALL.y) * height
	_shadow.position = Vector3(0.0, SHADOW_DEPTH, 0.0) + _card.global_basis.inverse() * fall
	_shadow_mat.set_shader_parameter("strength", SHADOW_STRENGTH * clampf(amount * 1.6, 0.0, 1.0))
	_shadow_mat.set_shader_parameter("softness", lerpf(SHADOW_SOFTNESS.x, SHADOW_SOFTNESS.y, amount))

func _ensure_shadow() -> void:
	if _shadow != null and is_instance_valid(_shadow):
		return
	var face: Vector2 = _card._card_face_size()
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = SHADOW_SHADER
	# Above the board (transparent pass); the opaque card still hides it by depth.
	_shadow_mat.render_priority = 1
	_shadow_mat.set_shader_parameter("card_size", face)
	_shadow_mat.set_shader_parameter("margin", SHADOW_MARGIN)
	var plane := PlaneMesh.new()
	plane.size = face + Vector2.ONE * (2.0 * SHADOW_MARGIN)
	_shadow = MeshInstance3D.new()
	_shadow.name = "LiftShadow"
	_shadow.mesh = plane
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.position = Vector3(0.0, SHADOW_DEPTH, 0.0)
	_shadow.visible = false
	_card.add_child(_shadow)

## Probe hook: the shadow's current strength (0 when hidden or never built).
func shadow_strength() -> float:
	if _shadow == null or not is_instance_valid(_shadow) or not _shadow.visible:
		return 0.0
	var value = _shadow_mat.get_shader_parameter("strength")
	return float(value) if value is float else 0.0

func _finish() -> void:
	tween = null
	_reset_pose()

func _reset_pose() -> void:
	var hand_mesh = _card.hand_mesh
	if hand_mesh == null or not is_instance_valid(hand_mesh):
		return
	hand_mesh.position = Vector3.ZERO
	hand_mesh.rotation = Vector3.ZERO
	hand_mesh.scale = Vector3.ONE
	_set_face_light(0.0)
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.visible = false
	if _chrome_active:
		for node_name in _chrome_homes:
			var node := _card.get_node_or_null(node_name) as Node3D
			if node != null:
				node.transform = _chrome_homes[node_name]
		_chrome_homes.clear()
		var power_label = _card.power_label
		if power_label != null:
			power_label.transform = _power_home
			if _power_hidden:
				power_label.visible = _power_was_visible and _card.current_zone == Card.Zone.FIELD
		_chrome_active = false
		_power_hidden = false
