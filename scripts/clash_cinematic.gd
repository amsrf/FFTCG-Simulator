extends Node3D
## Cinematic single-clash presentation.
##
## The rules resolve first (Game.clash_attacker_blocker). This node only replays
## the result with two visual proxies, so it never owns card state and never
## competes with Field/Hand layout.
##
## The real cards are hidden while the proxies perform. Survivors return to their
## exact captured transform; defeated proxies tumble, then hand off to the normal
## card-shatter effect. Game.break_card suppresses its own shatter for these two
## cards while the cinematic is running.

signal finished

const CARD_SCENE := preload("res://card.tscn")
const CARD_SHARDS := preload("res://card_shards.tscn")
const HALO_SHADER := preload("res://shaders/orb_halo.gdshader")

@export_group("Choreography")
@export var lift_height: float = 0.85
@export var lift_seconds: float = 0.22
## How long the cards take to turn into their clash orientation. The turn happens during the lift,
## before the retreat, so alignment is complete before the charge.
@export var align_seconds: float = 0.28
## Two cards whose projected centres are within this many pixels are treated as one column.
@export var same_column_pixels: float = 28.0
@export var windup_distance: float = 0.80
@export var windup_seconds: float = 0.32
@export_range(-70.0, 70.0) var windup_pitch_degrees: float = -32.0
## A deliberate beat with no movement at the end of the pull-back. This is the "moment of nothing" before the charge.
@export var windup_hold_seconds: float = 0.22
@export var charge_seconds: float = 0.075
@export var hitstop_seconds: float = 0.10
@export var recovery_seconds: float = 0.32
## Time spent tumbling intact before the airborne shatter.
@export var defeat_seconds: float = 0.55

@export_group("Defeat")
@export var knockback_speed: float = 2.4
@export var upward_impulse: float = 1.7
@export var gravity: float = 7.0
@export var tumble_speed: float = 520.0

@export_group("Impact")
@export var impact_flash_size: float = 0.65
@export var impact_flash_seconds: float = 0.12
@export var impact_flash_intensity: float = 2.0
@export var camera_shake_seconds: float = 0.22
@export var camera_shake_strength: float = 0.045
@export var random_seed: int = 0

var _attacker: Card = null
var _defender: Card = null
var _proxy_a: Card = null
var _proxy_b: Card = null
var _snap_a: Transform3D = Transform3D.IDENTITY
var _snap_b: Transform3D = Transform3D.IDENTITY
var _survives_a: bool = true
var _survives_b: bool = true
var _running: bool = false
var _camera: Camera3D = null
var _camera_home: Transform3D = Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()
var _defeated: Dictionary = {}


## Start the cinematic. `survives_*` comes from the already-resolved game state.
func play(attacker: Card, defender: Card, snap_a: Transform3D, snap_b: Transform3D,
		survives_a: bool, survives_b: bool) -> void:
	if _running:
		return
	_running = true
	_attacker = attacker
	_defender = defender
	_snap_a = snap_a
	_snap_b = snap_b
	_survives_a = survives_a
	_survives_b = survives_b
	_rng.seed = random_seed if random_seed != 0 else int(Time.get_ticks_usec())

	_camera = get_viewport().get_camera_3d()
	if _camera != null:
		_camera_home = _camera.global_transform

	_proxy_a = _make_proxy(attacker, snap_a)
	_proxy_b = _make_proxy(defender, snap_b)
	if _proxy_a == null or _proxy_b == null:
		_cleanup()
		return

	if attacker != null and is_instance_valid(attacker):
		attacker.set_hidden(true)
	if defender != null and is_instance_valid(defender):
		defender.set_hidden(true)

	await _choreograph()
	_cleanup()


func _make_proxy(source: Card, snapshot: Transform3D) -> Card:
	if source == null or not is_instance_valid(source):
		return null
	var proxy: Card = CARD_SCENE.instantiate()
	proxy.initialize(source.id, source.controller)
	add_child(proxy)
	proxy.enter_zone(Card.Zone.FIELD)
	proxy.global_transform = snapshot
	proxy.hide_power_display()
	proxy.set_highlight(false)
	proxy.set_process(false)
	proxy.process_mode = Node.PROCESS_MODE_DISABLED
	var area: Area3D = proxy.get_node_or_null("CardArea3D") as Area3D
	if area != null:
		area.monitoring = false
		area.monitorable = false
		area.input_ray_pickable = false
		area.collision_layer = 0
		area.collision_mask = 0
	return proxy


func _choreograph() -> void:
	var a0: Vector3 = _proxy_a.position
	var b0: Vector3 = _proxy_b.position
	var a_rot0: Vector3 = _proxy_a.rotation
	var b_rot0: Vector3 = _proxy_b.rotation
	var a_start: Vector3 = a0
	var b_start: Vector3 = b0
	var a_base_rot: Vector3 = a_rot0
	var b_base_rot: Vector3 = b_rot0
	var a_scale0: Vector3 = _proxy_a.scale
	var b_scale0: Vector3 = _proxy_b.scale
	var aligned: bool = not _same_column(a0, b0)
	var a_pose_rot: Vector3 = a_base_rot
	var b_pose_rot: Vector3 = b_base_rot
	if aligned:
		a_pose_rot = Vector3(0.0, _yaw_towards(a0, b0), 0.0)
		b_pose_rot = Vector3(0.0, _yaw_towards(b0, a0), 0.0)

	var travel: Vector3 = b0 - a0
	if travel.length_squared() < 0.0001:
		travel = Vector3.RIGHT
	var axis: Vector3 = travel.normalized()
	var lift: Vector3 = Vector3.UP * lift_height
	# Horizontal midpoint, before the lift. Using the lifted midpoint for the retreat direction would point
	# diagonally DOWN and lower both cards during the wind-up.
	var mid_ground: Vector3 = (a0 + b0) * 0.5
	var midpoint: Vector3 = mid_ground + lift
	# A top-edge-to-top-edge collision separates the CENTRES by a card height, not a card width.
	var card_height: float = 0.60 * maxf(_proxy_a.global_transform.basis.get_scale().x,
			_proxy_b.global_transform.basis.get_scale().x)
	var half_extent: float = card_height * 0.5 + 0.03
	var a_impact: Vector3 = midpoint - axis * half_extent
	var b_impact: Vector3 = midpoint + axis * half_extent

	var a_away: Vector3 = (a0 - mid_ground)
	var b_away: Vector3 = (b0 - mid_ground)
	if a_away.length_squared() < 0.0001:
		a_away = -axis
	if b_away.length_squared() < 0.0001:
		b_away = axis
	a_away = a_away.normalized()
	b_away = b_away.normalized()


	# Lift and align. Same-column cards stay upright (no roll); different-column cards first turn
	# their top edges toward each other, then the retreat/charge run along that facing axis.
	var lift_time: float = maxf(lift_seconds, align_seconds) if aligned else lift_seconds
	await _move_both(a0 + lift, b0 + lift,
		a_pose_rot, b_pose_rot,
		lift_time, Tween.TRANS_SINE, Tween.EASE_OUT)

	# Pitch around each card's own right axis while drawing it back.
	var a_windup := (Basis.from_euler(a_pose_rot) * Basis(Vector3.RIGHT, deg_to_rad(-windup_pitch_degrees if _proxy_a.controller == Card.OPPONENT else windup_pitch_degrees))).get_euler()
	var b_windup := (Basis.from_euler(b_pose_rot) * Basis(Vector3.RIGHT, deg_to_rad(-windup_pitch_degrees if _proxy_b.controller == Card.OPPONENT else windup_pitch_degrees))).get_euler()
	# Wind-up: retreat away from the midpoint.
	await _move_both(a0 + lift + a_away * windup_distance,
		b0 + lift + b_away * windup_distance,
		a_windup, b_windup,
		windup_seconds, Tween.TRANS_BACK, Tween.EASE_OUT)

	# The beat before the hit. No movement, no easing to distract from it; the cards are simply held back.
	await _wait(windup_hold_seconds)

	# Charge: very short, very sharp acceleration into the collision point.
	await _move_both(a_impact, b_impact,
		a_pose_rot, b_pose_rot,
		charge_seconds, Tween.TRANS_EXPO, Tween.EASE_IN)

	_impact_flash(midpoint)
	_shake_camera()
	await _wait(hitstop_seconds)

	var recovery: Array[Tween] = []
	if _survives_a:
		recovery.append(_start_recovery(_proxy_a, a_start, a_base_rot, a_scale0))
	else:
		_start_defeat(_proxy_a, -axis)
	if _survives_b:
		recovery.append(_start_recovery(_proxy_b, b_start, b_base_rot, b_scale0))
	else:
		_start_defeat(_proxy_b, axis)

	for tween in recovery:
		await tween.finished
	# Simulation time owns the delay, including slow motion and pause.
	while not _defeated.is_empty():
		await get_tree().process_frame



## Same column means the two centres project to the same screen x. That is the case where the
## cards should simply close vertically, with no in-plane turn and no sideways lean.
func _same_column(a_pos: Vector3, b_pos: Vector3) -> bool:
	if _camera == null or not is_instance_valid(_camera):
		return absf(a_pos.x - b_pos.x) <= 0.10
	var a_screen: Vector2 = _camera.unproject_position(_proxy_a.global_position)
	var b_screen: Vector2 = _camera.unproject_position(_proxy_b.global_position)
	return absf(a_screen.x - b_screen.x) <= same_column_pixels


## Yaw that makes this card local -Z (its top edge) point toward the other card on the board plane.
func _yaw_towards(from_pos: Vector3, to_pos: Vector3) -> float:
	var direction: Vector3 = to_pos - from_pos
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return 0.0
	direction = direction.normalized()
	return atan2(-direction.x, -direction.z)


func _move_both(a_pos: Vector3, b_pos: Vector3, a_rot: Vector3, b_rot: Vector3,
		seconds: float, trans: Tween.TransitionType, ease_type: Tween.EaseType,
		a_scale: Vector3 = Vector3.ZERO, b_scale: Vector3 = Vector3.ZERO) -> void:
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(trans).set_ease(ease_type)
	tween.tween_property(_proxy_a, "position", a_pos, seconds)
	tween.tween_property(_proxy_b, "position", b_pos, seconds)
	tween.tween_property(_proxy_a, "rotation", a_rot, seconds)
	tween.tween_property(_proxy_b, "rotation", b_rot, seconds)
	if a_scale != Vector3.ZERO:
		tween.tween_property(_proxy_a, "scale", a_scale, seconds)
	if b_scale != Vector3.ZERO:
		tween.tween_property(_proxy_b, "scale", b_scale, seconds)
	await tween.finished


func _start_recovery(proxy: Card, start_pos: Vector3, base_rot: Vector3,
		base_scale: Vector3 = Vector3.ZERO) -> Tween:
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(proxy, "position", start_pos, recovery_seconds)
	tween.parallel().tween_property(proxy, "rotation", base_rot, recovery_seconds)
	if base_scale != Vector3.ZERO:
		tween.parallel().tween_property(proxy, "scale", base_scale, recovery_seconds)
	return tween


func _start_defeat(proxy: Card, direction: Vector3) -> void:
	var spin_axis: Vector3 = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)).normalized()
	if spin_axis.length_squared() < 0.0001:
		spin_axis = Vector3.RIGHT
	_defeated[proxy] = {
		"age": 0.0,
		"velocity": direction * knockback_speed + Vector3.UP * upward_impulse,
		"spin": spin_axis * deg_to_rad(tumble_speed * _rng.randf_range(0.75, 1.2)),
	}


func _process(delta: float) -> void:
	if _defeated.is_empty():
		return
	for proxy in _defeated.keys():
		if proxy == null or not is_instance_valid(proxy):
			_defeated.erase(proxy)
			continue
		var state: Dictionary = _defeated[proxy]
		var velocity: Vector3 = state["velocity"]
		velocity.y -= gravity * delta
		state["velocity"] = velocity
		proxy.position += velocity * delta
		var spin: Vector3 = state["spin"]
		if spin.length_squared() > 0.00001:
			proxy.quaternion = Quaternion(spin.normalized(), spin.length() * delta) * proxy.quaternion
		state["age"] = float(state["age"]) + delta
		if float(state["age"]) >= defeat_seconds:
			_shatter_defeated(proxy, velocity, spin)
			_defeated.erase(proxy)



func _shatter_defeated(proxy: Card, velocity: Vector3, spin: Vector3) -> void:
	var shards := CARD_SHARDS.instantiate()
	# Keep fragments alive after this cinematic releases its visual proxies.
	get_parent().add_child(shards)
	var game_field := get_parent().get_node_or_null("Field") as Node3D
	if game_field != null:
		shards.floor_world_y = game_field.global_position.y
	shards.burst_from_card(proxy, global_basis * velocity, global_basis.orthonormalized() * spin)
	proxy.visible = false


func _impact_flash(point: Vector3) -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(impact_flash_size, impact_flash_size)
	quad.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = HALO_SHADER
	material.set_shader_parameter("halo_color", Color(1.0, 0.86, 0.55, 1.0))
	material.set_shader_parameter("intensity", impact_flash_intensity)
	material.set_shader_parameter("falloff", 2.0)
	material.set_shader_parameter("skirt_amount", 0.8)
	quad.material_override = material
	add_child(quad)
	var basis: Basis = _camera.global_transform.basis if _camera != null else Basis()
	quad.global_transform = Transform3D(basis, point)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(quad, "scale", Vector3.ONE * 1.6, impact_flash_seconds)
	tween.tween_method(func(value: float) -> void:
		material.set_shader_parameter("intensity", value),
		impact_flash_intensity, 0.0, impact_flash_seconds)
	tween.chain().tween_callback(quad.queue_free)


func _shake_camera() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var base: Vector3 = _camera_home.origin
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for _i in range(6):
		var offset := Vector3(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0)) * camera_shake_strength
		tween.tween_property(_camera, "global_position", base + offset,
			camera_shake_seconds / 7.0)
	tween.tween_property(_camera, "global_position", base,
		camera_shake_seconds / 7.0)


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout


func _cleanup() -> void:
	if _proxy_a != null and is_instance_valid(_proxy_a):
		_proxy_a.queue_free()
	if _proxy_b != null and is_instance_valid(_proxy_b):
		_proxy_b.queue_free()
	_proxy_a = null
	_proxy_b = null
	_defeated.clear()
	if _attacker != null and is_instance_valid(_attacker):
		_attacker.set_hidden(false)
		if _survives_a and _attacker.is_drawn_on_field():
			_attacker.global_transform = _snap_a
	if _defender != null and is_instance_valid(_defender):
		_defender.set_hidden(false)
		if _survives_b and _defender.is_drawn_on_field():
			_defender.global_transform = _snap_b
	if _camera != null and is_instance_valid(_camera):
		_camera.global_transform = _camera_home
	_camera = null
	_running = false
	finished.emit()
