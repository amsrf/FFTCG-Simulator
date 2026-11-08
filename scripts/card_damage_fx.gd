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

## Recoil: a quick pop off the table, a scale-up and a tilt, then a damped settle. Indexed by damage tier.
const REACTION_SECONDS := 0.62
const REACTION_LIFT := [0.055, 0.085, 0.115, 0.148]
const REACTION_SCALE := [0.035, 0.060, 0.085, 0.110]
const REACTION_YAW_DEG := [2.4, 3.6, 5.0, 6.4]
const REACTION_ROLL_DEG := [1.0, 1.4, 2.0, 2.8]
const REACTION_SIDE := [0.006, 0.012, 0.018, 0.025]

## Earth launch follows gravity and returns exactly to the mesh's resting pose.
const EARTH_LAUNCH_HEIGHTS: Array[float] = [1.0, 1.6, 2.2, 2.9]
const EARTH_LAUNCH_GRAVITY := 9.8
signal earth_landed

## Card is a Node3D; kept untyped so this file and card.gd do not depend on each other's class_name.
var _card: Node3D
## The running recoil OR launch tween. Starting either one stops the other.
var tween: Tween = null
## When the falling card first touches the board, measured from the start of the launch (after any delay).
var earth_contact_seconds := 0.0

var _bounce_curve: Curve = null
var _wiggle_curve: Curve = null
var _peak_lift: float = 0.0
var _peak_scale: float = 0.0
var _peak_yaw: float = 0.0
var _peak_roll: float = 0.0
var _peak_side: float = 0.0
var _earth_chrome_active := false
var _earth_edge_home := Transform3D.IDENTITY
var _earth_power_was_visible := false

func _init(card: Node3D) -> void:
	_card = card

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
	_ensure_curves()
	var tier: int = VfxEvent.damage_tier_for(damage)
	_peak_lift = float(REACTION_LIFT[tier])
	_peak_scale = float(REACTION_SCALE[tier])
	_peak_yaw = float(REACTION_YAW_DEG[tier])
	_peak_roll = float(REACTION_ROLL_DEG[tier])
	_peak_side = float(REACTION_SIDE[tier])
	normalize()
	var t := _card.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_method(_set_reaction_pose, 0.0, 1.0, REACTION_SECONDS)
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
	# Small bounded wavering replaces full turns. The envelope fades away
	# before touchdown, preserving the planned landing pose.
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
		var orientation := Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.UP, angles.y) * Basis(Vector3.BACK, angles.z)
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
	var edge := _card.get_node_or_null("CardEdge") as Node3D
	_earth_edge_home = edge.transform if edge != null else Transform3D.IDENTITY
	var power_label = _card.power_label
	_earth_power_was_visible = power_label.visible if power_label != null else false
	_earth_chrome_active = true
	if power_label != null:
		power_label.visible = false
	var edge_home := _earth_edge_home
	var apply_pose := func(pose: Transform3D) -> void:
		if not card.is_drawn_on_field():
			return
		hand_mesh.transform = pose
		if is_instance_valid(edge):
			edge.transform = pose * edge_home
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

func _ensure_curves() -> void:
	if _bounce_curve != null:
		return
	# The non-negative envelope is the actual jump: fast attack, a short hang,
	# then a small damped bounce back to rest.
	_bounce_curve = Curve.new()
	_bounce_curve.min_value = -0.12
	_bounce_curve.max_value = 1.05
	for point in [Vector2(0.00, 0.00), Vector2(0.07, 1.00), Vector2(0.20, 0.82), Vector2(0.34, 0.90),
			Vector2(0.49, 0.36), Vector2(0.62, 0.20), Vector2(0.74, -0.05), Vector2(0.86, 0.04),
			Vector2(0.94, -0.02), Vector2(1.00, 0.00)]:
		_bounce_curve.add_point(point)
	# Signed curve for yaw/roll/side motion: the card rocks one way, then the
	# other, shrinking to zero. Separate from the lift so the settle can shake
	# without the card sinking through the board.
	_wiggle_curve = Curve.new()
	_wiggle_curve.min_value = -1.0
	_wiggle_curve.max_value = 1.0
	for point in [Vector2(0.00, 0.00), Vector2(0.07, 1.00), Vector2(0.18, 0.45), Vector2(0.30, -0.55),
			Vector2(0.43, 0.34), Vector2(0.56, -0.20), Vector2(0.68, 0.12), Vector2(0.80, -0.06),
			Vector2(0.90, 0.03), Vector2(1.00, 0.00)]:
		_wiggle_curve.add_point(point)

func _set_reaction_pose(progress: float) -> void:
	var hand_mesh = _card.hand_mesh
	if hand_mesh == null or not is_instance_valid(hand_mesh):
		return
	if not _card.is_drawn_on_field():
		_reset_pose()
		return
	var bounce: float = _bounce_curve.sample(progress)
	var wiggle: float = _wiggle_curve.sample(progress)
	var yaw: float = deg_to_rad(_peak_yaw * wiggle)
	var roll: float = deg_to_rad(_peak_roll * wiggle)
	var pitch: float = deg_to_rad(-_peak_yaw * 0.22 * bounce)
	hand_mesh.position = Vector3(_peak_side * wiggle, _peak_lift * bounce, 0.0)
	hand_mesh.rotation = Vector3(pitch, yaw, roll)
	hand_mesh.scale = Vector3.ONE * (1.0 + _peak_scale * bounce)

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
	if _earth_chrome_active:
		var edge := _card.get_node_or_null("CardEdge") as Node3D
		if edge != null:
			edge.transform = _earth_edge_home
		var power_label = _card.power_label
		if power_label != null:
			power_label.visible = _earth_power_was_visible and _card.current_zone == Card.Zone.FIELD
		_earth_chrome_active = false
