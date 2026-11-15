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

## RECOIL, modelled on the reference clip (~/Desktop/Clips/damage, the wolf, frames 62-102 at 60 fps). Tracking it
## showed AUTHORED curves, not a physics step: it snaps up in one frame, drifts higher while it hangs, and its fall
## EASES into the board (it slows before contact - free fall would not). Only the landing behaves like a simulation: a
## damped spring rocks it edge to edge with one small hop. What sells it there is lighting, so this does the same:
##   SNAP + HANG   lift (world Y), tip toward the camera about the near (bottom) edge, a slight turn to the left;
##   FALL          ease-in-out back to the board;
##   LANDING       a damped spring roll about the long axis (the low edge touching first), plus one hop;
##   SHADING       the face brightens as it turns toward the light (camera side), ~+15% at the tip like the wolf,
##                 and flickers as it rocks (card.gdshader `face_light`);
##   SHADOW        a soft board shadow that grows with height.
## Every hit is ROLLED (roll_reaction): each size and timing below is a base that the roll varies within its range,
## so two hits never look the same but always look like the same kind of hit.
## Timeline (seconds, before the roll):
const REACTION_RISE := 0.03
const REACTION_HANG_END := 0.17
const REACTION_FALL := 0.19
## The rock starts this long BEFORE contact: the low edge meets the board first.
const REACTION_ROCK_LEAD := 0.06
## How long the landing (rock + hops) lasts after contact; the spring is faded to exactly zero at the end.
const REACTION_SETTLE := 0.50
## Sizes, by damage tier. The tip stays near 20 deg: on this ~67 deg board camera a flat card is already 23 deg from
## facing it, so more tip makes the card look SHORTER, not tipped (measured; see AGENTS.md).
const REACTION_LIFT := [0.30, 0.35, 0.40, 0.45]
const REACTION_PITCH_DEG := [18.0, 20.0, 22.0, 24.0]
const REACTION_YAW_DEG := [3.0, 3.5, 4.0, 4.5]
const REACTION_ROLL_DEG := [6.0, 7.0, 8.0, 9.0]
const REACTION_HOP := [0.04, 0.05, 0.06, 0.07]
## The landing spring: one full rock's period and how fast it dies. Weak damping on purpose (the user wanted more
## bounce): about six swings before it is still.
const ROCK_PERIOD := 0.15
const ROCK_DAMPING := 3.2
const HOP_SECONDS := 0.18
## A second, smaller hop right after the first.
const HOP2_SHARE := 0.35
const HOP2_SECONDS := 0.12
## The roll's ranges: multipliers on the base (or degrees added, for the tip).
const VARY_LIFT := Vector2(0.85, 1.15)
const VARY_PITCH_DEG := Vector2(-3.0, 3.0)
const VARY_YAW := Vector2(0.6, 1.4)
## Chance the snap turns LEFT (as in the reference); otherwise it turns right.
const YAW_LEFT_CHANCE := 0.7
const VARY_ROLL := Vector2(0.8, 1.25)
const VARY_ROCK_PERIOD := Vector2(0.85, 1.15)
const VARY_DAMPING := Vector2(0.8, 1.2)
const VARY_HOP := Vector2(0.75, 1.3)
const VARY_HANG := Vector2(0.85, 1.2)
const VARY_FALL := Vector2(0.9, 1.15)
const VARY_ROCK_LEAD := Vector2(0.5, 1.2)
## Card face half extents (metres, card-local); matches card.tres.
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

## Rolls one hit: every size and timing varied within its VARY_* range, the turn's direction, and which edge lands
## first. Static and seeded, so a probe can sweep many seeds.
static func roll_reaction(tier: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	tier = clampi(tier, 0, REACTION_LIFT.size() - 1)
	var vary := func(range_value: Vector2) -> float: return rng.randf_range(range_value.x, range_value.y)
	var hang_end: float = REACTION_HANG_END * vary.call(VARY_HANG)
	var land: float = hang_end + REACTION_FALL * vary.call(VARY_FALL)
	var yaw_sign := 1.0 if rng.randf() < YAW_LEFT_CHANCE else -1.0
	return {
		"rise": REACTION_RISE,
		"hang_end": hang_end,
		"land": land,
		"rock_start": land - REACTION_ROCK_LEAD * vary.call(VARY_ROCK_LEAD),
		"end": land + REACTION_SETTLE,
		"lift": float(REACTION_LIFT[tier]) * vary.call(VARY_LIFT),
		"pitch": float(REACTION_PITCH_DEG[tier]) + vary.call(VARY_PITCH_DEG),
		"yaw": float(REACTION_YAW_DEG[tier]) * vary.call(VARY_YAW) * yaw_sign,
		"roll": float(REACTION_ROLL_DEG[tier]) * vary.call(VARY_ROLL),
		"rock_sign": 1.0 if rng.randf() < 0.5 else -1.0,
		"rock_period": ROCK_PERIOD * vary.call(VARY_ROCK_PERIOD),
		"rock_damping": ROCK_DAMPING * vary.call(VARY_DAMPING),
		"hop": float(REACTION_HOP[tier]) * vary.call(VARY_HOP),
	}

## The hit's envelope at `t`: x = lift (0..~1.06 of the peak), y = tip (0..~1.12), z = turn (0..1). Snap, hang
## (drifting a little higher and tipping a little further), then an ease-in-out fall that slows into the board.
static func reaction_envelope(t: float, p: Dictionary) -> Vector3:
	var rise: float = p.rise
	var hang_end: float = p.hang_end
	var land: float = p.land
	if t <= 0.0 or t >= land:
		return Vector3.ZERO
	if t < rise:
		var up := _ease_out(t / rise)
		return Vector3(up, up, up)
	if t < hang_end:
		var u := smoothstep(0.0, 1.0, (t - rise) / (hang_end - rise))
		return Vector3(1.0 + 0.06 * u, 1.0 + 0.12 * u, 1.0)
	var down := 1.0 - _smoother((t - hang_end) / (land - hang_end))
	return Vector3(1.06 * down, 1.12 * down, down)

## The landing spring at `t`: x = roll (-1..1, signed; one long edge down), y = hop height (0..1 of the first hop).
static func landing_spring(t: float, p: Dictionary) -> Vector2:
	var land: float = p.land
	var end: float = p.end
	var rock_start: float = p.rock_start
	var roll := 0.0
	if t > rock_start and t < end:
		var tau := t - rock_start
		roll = exp(-float(p.rock_damping) * tau) * sin(TAU * tau / float(p.rock_period))
		roll *= 1.0 - smoothstep(end - 0.10, end, t)
	var hop := 0.0
	var after := t - land
	if after > 0.0 and after < HOP_SECONDS:
		hop = sin(PI * after / HOP_SECONDS)
	elif after >= HOP_SECONDS and after < HOP_SECONDS + HOP2_SECONDS:
		hop = HOP2_SHARE * sin(PI * (after - HOP_SECONDS) / HOP2_SECONDS)
	return Vector2(roll, hop)

## The HandMesh pose at `t` for the rolled hit `p`, in the CARD'S LOCAL frame (local +Y is world up; field cards are
## turned half a turn about Y, so never convert this through the card's world basis). `scale` divides the world
## metres into local units. LIFT * YAW * PITCH * ROLL: the tip pivots on the near edge, the turn and the roll about the
## card's centre; the roll's low edge is lifted back onto the board so no corner enters it.
static func reaction_pose(t: float, far_sign: float, p: Dictionary, scale: float = 1.0) -> Transform3D:
	var env := reaction_envelope(t, p)
	var spring := landing_spring(t, p)
	if env == Vector3.ZERO and spring == Vector2.ZERO:
		return Transform3D.IDENTITY
	var pitch_angle := deg_to_rad(float(p.pitch)) * env.y
	var pitch_basis := Basis(Vector3.RIGHT, pitch_angle * far_sign)
	var pivot := Vector3(0.0, 0.0, HALF_FACE.y * far_sign)
	var pitch := Transform3D(pitch_basis, pivot - pitch_basis * pivot)
	var roll_angle := deg_to_rad(float(p.roll)) * spring.x * float(p.rock_sign)
	var roll := Transform3D(Basis(Vector3.BACK, roll_angle), Vector3.ZERO)
	# Positive about world up is counter-clockwise seen from the downward-looking camera: the turn to the left.
	var yaw := Transform3D(Basis(Vector3.UP, deg_to_rad(float(p.yaw)) * env.z), Vector3.ZERO)
	var height := (float(p.lift) * env.x + float(p.hop) * spring.y) / scale \
		+ HALF_FACE.x * absf(sin(roll_angle)) * cos(pitch_angle)
	return Transform3D(Basis.IDENTITY, Vector3.UP * height) * yaw * pitch * roll

func _set_reaction_pose(seconds: float) -> void:
	var hand_mesh = _card.hand_mesh
	if hand_mesh == null or not is_instance_valid(hand_mesh):
		return
	if not _card.is_drawn_on_field() or _params.is_empty():
		_reset_pose()
		return
	var card_scale: float = maxf(_card.global_basis.get_scale().y, 0.0001)
	var pose := reaction_pose(seconds, _far_sign, _params, card_scale)
	hand_mesh.transform = pose
	_apply_chrome(pose)
	_set_face_light(face_light_for(pose))
	var tip: float = deg_to_rad(float(_params.pitch))
	var height: float = pose.origin.y * card_scale + HALF_FACE.y * sin(tip * reaction_envelope(seconds, _params).y)
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
