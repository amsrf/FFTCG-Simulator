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
##
## One look for every clash, First Strike included: the exchange shows only WHO SURVIVED. A dulled card is turned
## STRAIGHT before anything else moves, stays straight through the whole exchange (no turning to face the other card,
## whatever the columns), and is turned back to dulled once it is home again. An unblocked attack is the
## same strike aimed at the defending player (play_player_strike()).

signal finished
## play_player_strike(): the strike has landed and the card has started its glide home. The damage may be dealt from
## here (the zoom then overlaps the glide). Emitted on EVERY path, including a strike that had nothing to play.
signal handoff
## play_player_strike(): every proxy is gone and the real cards are shown again.
signal strike_finished

const CARD_SCENE := preload("res://scenes/cards/card.tscn")
const CARD_SHARDS := preload("res://scenes/cards/card_shards.tscn")
const HALO_SHADER := preload("res://shaders/orb_halo.gdshader")
const EDGE_WAVE_SHADER := preload("res://shaders/player_impact_wave.gdshader")

@export_group("Choreography")
@export var lift_height: float = 0.85
@export var lift_seconds: float = 0.22
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

## A dulled card turns straight before the clash, and back to dulled after it is home.
@export var straighten_seconds: float = 0.16
@export var redull_seconds: float = 0.20

@export_group("Player Strike")
## The defending player is a point at the screen's horizontal centre, this many pixels past its top (or bottom) edge.
@export var player_offscreen_pixels: float = 12.0
## Party members charge side by side: the gap between their contact points, in card widths.
@export var party_contact_spacing: float = 1.1
## HIT STUN: the striker stays STILL at the player (no tremble: the user's call) and is flashed white
## (`hitstun_whiteout` at contact, gone after `hitstun_flash_seconds`). The hold and the bounce scale with the
## attacker's strength (`hitstun_strength_range`, a multiplier from weakest to strongest).
@export var hitstun_seconds: float = 0.40
@export var hitstun_whiteout: float = 0.75
@export var hitstun_flash_seconds: float = 0.16
@export var hitstun_strength_range := Vector2(0.8, 1.35)
## The BOUNCE off the player: knocked back this far (m), leaning back by `bounce_pitch_degrees`, then it HANGS there.
@export var bounce_distance: float = 0.38
@export var bounce_seconds: float = 0.18
@export var bounce_pitch_degrees: float = 18.0
@export var hang_seconds: float = 0.15
## The calm GLIDE home (no spring, no overshoot — the clash's return is the snappy one), then it dulls again.
@export var glide_seconds: float = 0.85
## The impact at the player's EDGE: a wide flat shockwave in the screen plane (m), and a camera shake that PUSHES
## toward the player and settles back (`player_shake_push` m, damped over `player_shake_seconds`).
@export var edge_wave_size := Vector2(5.0, 1.1)
@export var edge_wave_seconds: float = 0.45
@export var edge_wave_intensity: float = 2.2
@export var player_shake_push: float = 0.07
@export var player_shake_seconds: float = 0.45

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

## POWER DRIVES THE BLOW. Each card's power maps to a strength 0..1 between these two values; a stronger card draws
## back further, charges faster (it leaves later and still arrives on the same frame), drives the meeting point into
## its opponent's half, and throws a defeated opponent harder.
@export_group("Power")
@export var weak_power: int = 2000
@export var strong_power: int = 10000
## Wind-up distance multiplier at strength 0 and 1.
@export var windup_scale_range := Vector2(0.70, 1.40)
## Charge time multiplier at strength 0 and 1 (lower = faster).
@export var charge_scale_range := Vector2(1.70, 0.70)
## How far the meeting point moves toward the weaker card, in card heights, at the largest strength gap.
@export var impact_push: float = 0.45
## Knockback multiplier on a defeated card at its opponent's strength 0 and 1.
@export var knockback_scale_range := Vector2(0.75, 1.65)

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
## Strength 0..1 of the attacker (a) and the defender (b), from their power when the clash started.
var _strength_a: float = 0.5
var _strength_b: float = 0.5
## Each real card's hidden state when the cinematic began, restored for a defeated card: one that broke is already
## swallowed (hidden) by its pit, and un-hiding it would draw it on top of the pit.
var _was_hidden_a: bool = false
var _was_hidden_b: bool = false
## play_player_strike(): one {card, proxy, snap, hidden} per attacking card.
var _strikers: Array = []
var _handed_off: bool = false


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
	_strength_a = strength_for(attacker)
	_strength_b = strength_for(defender)

	_camera = get_viewport().get_camera_3d()
	if _camera != null:
		_camera_home = _camera.global_transform

	_proxy_a = _make_proxy(attacker, snap_a)
	_proxy_b = _make_proxy(defender, snap_b)
	if _proxy_a == null or _proxy_b == null:
		_cleanup()
		return

	if attacker != null and is_instance_valid(attacker):
		_was_hidden_a = not attacker.visible
		attacker.set_hidden(true)
	if defender != null and is_instance_valid(defender):
		_was_hidden_b = not defender.visible
		defender.set_hidden(true)

	await _choreograph()
	_cleanup()


## A card's strength 0..1 for the choreography: its current power between weak_power and strong_power.
func strength_for(card: Card) -> float:
	if card == null or not is_instance_valid(card):
		return 0.5
	return clampf(inverse_lerp(float(weak_power), float(strong_power), float(card.power)), 0.0, 1.0)


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
	var a_rest: Quaternion = _proxy_a.quaternion
	var b_rest: Quaternion = _proxy_b.quaternion
	var a_straight: Quaternion = _straight_rotation(_attacker, a_rest)
	var b_straight: Quaternion = _straight_rotation(_defender, b_rest)
	var a_scale0: Vector3 = _proxy_a.scale
	var b_scale0: Vector3 = _proxy_b.scale

	# STRAIGHT FIRST, in place: a dulled card would otherwise wind up and charge at its tilt. The cards stay straight
	# for the whole exchange; they never turn to face each other.
	await _run([[_proxy_a, a0, a_straight], [_proxy_b, b0, b_straight]], straighten_seconds,
		Tween.TRANS_SINE, Tween.EASE_IN_OUT)

	var travel: Vector3 = b0 - a0
	travel.y = 0.0
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
	# The stronger card drives the collision into the weaker one's half.
	var contact: Vector3 = midpoint + axis * (_strength_a - _strength_b) * impact_push * card_height
	var a_impact: Vector3 = contact - axis * half_extent
	var b_impact: Vector3 = contact + axis * half_extent
	var a_away: Vector3 = a0 - mid_ground
	var b_away: Vector3 = b0 - mid_ground
	a_away.y = 0.0
	b_away.y = 0.0
	a_away = a_away.normalized() if a_away.length_squared() > 0.0001 else -axis
	b_away = b_away.normalized() if b_away.length_squared() > 0.0001 else axis

	await _run([[_proxy_a, a0 + lift, a_straight], [_proxy_b, b0 + lift, b_straight]], lift_seconds,
		Tween.TRANS_SINE, Tween.EASE_OUT)

	# Wind-up: retreat away from the midpoint, leaning back about the card's own right axis.
	await _run([
		[_proxy_a, a0 + lift + a_away * windup_distance * _windup_scale(_strength_a), _leaning(_proxy_a, a_straight)],
		[_proxy_b, b0 + lift + b_away * windup_distance * _windup_scale(_strength_b), _leaning(_proxy_b, b_straight)],
	], windup_seconds, Tween.TRANS_BACK, Tween.EASE_OUT)

	# The beat before the hit. No movement, no easing to distract from it; the cards are simply held back.
	await _wait(windup_hold_seconds)

	# Charge: very short, very sharp acceleration into the collision point. Each card at its own speed; the faster
	# one leaves later, so both arrive on the same frame.
	var a_time: float = _charge_time(_strength_a)
	var b_time: float = _charge_time(_strength_b)
	var longest: float = maxf(a_time, b_time)
	var charge: Tween = create_tween().set_parallel(true)
	charge.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_pose(charge, _proxy_a, a_impact, a_straight, a_time, longest - a_time)
	_pose(charge, _proxy_b, b_impact, b_straight, b_time, longest - b_time)
	await charge.finished

	_impact_flash(contact)
	_shake_camera(maxf(_strength_a, _strength_b))
	await _wait(hitstop_seconds)

	var recovery: Array[Tween] = []
	if _survives_a:
		recovery.append(_start_recovery(_proxy_a, a0, a_straight, a_scale0))
	else:
		_start_defeat(_proxy_a, -axis, _strength_b)
	if _survives_b:
		recovery.append(_start_recovery(_proxy_b, b0, b_straight, b_scale0))
	else:
		_start_defeat(_proxy_b, axis, _strength_a)
	for tween in recovery:
		await tween.finished
	# Home again: a survivor turns back to how it rested (dulled, if it was).
	var back: Array = []
	if _survives_a:
		back.append([_proxy_a, a0, a_rest])
	if _survives_b:
		back.append([_proxy_b, b0, b_rest])
	await _run(back, redull_seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	# Simulation time owns the delay, including slow motion and pause.
	while not _defeated.is_empty():
		await get_tree().process_frame


## AN UNBLOCKED ATTACK: every attacking card charges the defending player. The player is not on the board, so they are
## a point at the screen's horizontal centre, `player_offscreen_pixels` past the TOP edge (the opponent) or the BOTTOM
## edge (`hit_bottom`: the local player), at the height the cards are lifted to. Same beats as the exchange, and just
## as STRAIGHT: straighten, lift, wind up, hold, charge, impact, return home, dull again. Nothing is defeated.
func play_player_strike(attackers: Array, hit_bottom: bool) -> void:
	if _running:
		_hand_off()
		return
	_running = true
	_rng.seed = random_seed if random_seed != 0 else int(Time.get_ticks_usec())
	_camera = get_viewport().get_camera_3d()
	if _camera != null:
		_camera_home = _camera.global_transform
	for card in attackers:
		if card == null or not is_instance_valid(card):
			continue
		var proxy: Card = _make_proxy(card, card.global_transform)
		if proxy == null:
			continue
		_strikers.append({"card": card, "proxy": proxy, "snap": card.global_transform, "hidden": not card.visible})
		card.set_hidden(true)
	if not _strikers.is_empty():
		await _choreograph_player_strike(hit_bottom)
	_hand_off()
	_cleanup()
	strike_finished.emit()


func is_handed_off() -> bool:
	return _handed_off


func _hand_off() -> void:
	if _handed_off:
		return
	_handed_off = true
	handoff.emit()


func _choreograph_player_strike(hit_bottom: bool) -> void:
	var count: int = _strikers.size()
	var proxies: Array = []
	var starts: Array = []
	var rests: Array = []
	var straights: Array = []
	var scales: Array = []
	var strengths: Array = []
	for entry in _strikers:
		var proxy: Card = entry.proxy
		proxies.append(proxy)
		starts.append(proxy.position)
		rests.append(proxy.quaternion)
		straights.append(_straight_rotation(entry.card, proxy.quaternion))
		scales.append(proxy.scale)
		strengths.append(strength_for(entry.card))

	var straighten: Array = []
	for i in count:
		straighten.append([proxies[i], starts[i], straights[i]])
	await _run(straighten, straighten_seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT)

	var lift: Vector3 = Vector3.UP * lift_height
	var card_scale: float = (proxies[0] as Card).global_transform.basis.get_scale().x
	var half_extent: float = 0.60 * card_scale * 0.5 + 0.03
	var target: Vector3 = to_local(player_point(hit_bottom, (proxies[0] as Card).global_position.y + lift_height))
	# Side by side along the screen's horizontal, so a party does not pile into one point.
	var across: Vector3 = Vector3.RIGHT
	if _camera != null:
		across = global_basis.inverse() * _camera.global_basis.x
		across.y = 0.0
		across = across.normalized() if across.length_squared() > 0.0001 else Vector3.RIGHT
	var contacts: Array = []
	var axes: Array = []
	for i in count:
		var contact: Vector3 = target + across * (float(i) - float(count - 1) * 0.5) \
				* party_contact_spacing * 0.429 * card_scale
		var axis: Vector3 = contact - (starts[i] + lift)
		axis.y = 0.0
		axes.append(axis.normalized() if axis.length_squared() > 0.0001 else Vector3.FORWARD)
		contacts.append(contact)

	var lifting: Array = []
	var winding: Array = []
	for i in count:
		lifting.append([proxies[i], starts[i] + lift, straights[i]])
		winding.append([proxies[i], starts[i] + lift - axes[i] * windup_distance * _windup_scale(strengths[i]),
			_leaning(proxies[i], straights[i])])
	await _run(lifting, lift_seconds, Tween.TRANS_SINE, Tween.EASE_OUT)
	await _run(winding, windup_seconds, Tween.TRANS_BACK, Tween.EASE_OUT)
	await _wait(windup_hold_seconds)

	# Charge, straight: the top edge meets the player point; the faster card leaves later, so all arrive together.
	var longest: float = 0.0
	var strongest: float = 0.0
	for strength in strengths:
		longest = maxf(longest, _charge_time(strength))
		strongest = maxf(strongest, strength)
	var charge: Tween = create_tween().set_parallel(true)
	charge.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	for i in count:
		var time: float = _charge_time(strengths[i])
		_pose(charge, proxies[i], contacts[i] - axes[i] * half_extent, straights[i], time, longest - time)
	await charge.finished

	# IMPACT AT THE PLAYER'S EDGE: the round flash, a wide flat shockwave, and a shake that pushes toward the player.
	var stun_scale: float = lerpf(hitstun_strength_range.x, hitstun_strength_range.y, strongest)
	_impact_flash(to_global(target))
	_edge_wave(to_global(target), stun_scale)
	var push: Vector3 = Vector3.ZERO
	for axis in axes:
		push += axis
	_push_camera(global_basis * push.normalized() if push.length_squared() > 0.0001 else Vector3.ZERO, stun_scale)

	# HIT STUN: every striker holds still at its contact point, flashed white. All at once: a party hits as one.
	var contact_poses: Array = []
	for i in count:
		contact_poses.append(proxies[i].position)
	var stun: float = hitstun_seconds * stun_scale
	var stunning: Tween = create_tween()
	stunning.tween_method(func(t: float) -> void:
		var flash: float = 1.0 - clampf(t / maxf(hitstun_flash_seconds, 0.0001), 0.0, 1.0)
		for i in count:
			_set_whiteout(proxies[i], hitstun_whiteout * flash * flash), 0.0, stun, stun)
	await stunning.finished

	# BOUNCE off the player, leaning back, and HANG there.
	var bounced: Array = []
	for i in count:
		_set_whiteout(proxies[i], 0.0)
		# Leaning BACK, the same way as the wind-up (whose sign is mirrored for the opponent's cards).
		var pitch: float = deg_to_rad(bounce_pitch_degrees if proxies[i].controller == Card.OPPONENT \
				else -bounce_pitch_degrees)
		bounced.append([proxies[i], contact_poses[i] - axes[i] * bounce_distance * stun_scale,
			straights[i] * Quaternion(Vector3.RIGHT, pitch)])
	await _run(bounced, bounce_seconds, Tween.TRANS_QUART, Tween.EASE_OUT)
	await _wait(hang_seconds)
	_restore_camera()

	# GLIDE home: slow and calm. The damage may be dealt from here on.
	var gliding: Tween = create_tween().set_parallel(true)
	gliding.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in count:
		_pose(gliding, proxies[i], starts[i], straights[i], glide_seconds)
	_hand_off()
	await gliding.finished
	var back: Array = []
	for i in count:
		back.append([proxies[i], starts[i], rests[i]])
	await _run(back, redull_seconds, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


func _set_whiteout(proxy: Card, value: float) -> void:
	if proxy == null or not is_instance_valid(proxy):
		return
	var mat: ShaderMaterial = proxy.get("mat") as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("whiteout", value)


## The wide flat shockwave at the player's edge: a camera-facing quad, longer across the screen than it is tall.
func _edge_wave(point: Vector3, size_scale: float) -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = edge_wave_size * size_scale
	quad.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = EDGE_WAVE_SHADER
	material.set_shader_parameter("intensity", edge_wave_intensity)
	material.set_shader_parameter("progress", 0.0)
	material.render_priority = 10
	quad.material_override = material
	quad.extra_cull_margin = 2.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	var basis: Basis = _camera.global_transform.basis if _camera != null else Basis()
	quad.global_transform = Transform3D(basis, point)
	var tween: Tween = create_tween()
	tween.tween_method(func(value: float) -> void:
		material.set_shader_parameter("progress", value), 0.0, 1.0, edge_wave_seconds)
	tween.tween_callback(quad.queue_free)


## A DIRECTIONAL shake: the camera is jolted `player_shake_push` toward the player at once, then swings back and
## settles about its home (a damped cosine), with a little sideways jitter. It is exactly home at the end.
var _push_tween: Tween = null

func _push_camera(direction: Vector3, push_scale: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var dir: Vector3 = direction
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO
	var side: Vector3 = dir.cross(Vector3.UP)
	var home: Vector3 = _camera_home.origin
	var amount: float = player_shake_push * push_scale
	var seconds: float = maxf(player_shake_seconds, 0.0001)
	_push_tween = create_tween()
	_push_tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(_camera):
			return
		var u: float = t / seconds
		var envelope: float = exp(-5.0 * u) * (1.0 - u)
		var along: float = cos(u * TAU * 2.2) * envelope
		var jitter: float = sin(u * TAU * 7.0) * envelope * 0.35
		_camera.global_position = home + dir * amount * along + side * amount * jitter, 0.0, seconds, seconds)
	_push_tween.tween_callback(_restore_camera)


func _restore_camera() -> void:
	if _push_tween != null and _push_tween.is_valid():
		_push_tween.kill()
	_push_tween = null
	if _camera != null and is_instance_valid(_camera):
		_camera.global_position = _camera_home.origin


## The defending player's point in WORLD space: the screen's horizontal centre, `player_offscreen_pixels` beyond the
## top edge (or the bottom edge), on the horizontal plane at `plane_y`.
func player_point(hit_bottom: bool, plane_y: float) -> Vector3:
	var camera: Camera3D = _camera if _camera != null and is_instance_valid(_camera) else get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(0.0, plane_y, 0.0)
	var view: Vector2 = get_viewport().get_visible_rect().size
	var screen := Vector2(view.x * 0.5,
		view.y + player_offscreen_pixels if hit_bottom else -player_offscreen_pixels)
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	if absf(direction.y) < 0.0001:
		return Vector3(origin.x, plane_y, origin.z)
	return origin + direction * ((plane_y - origin.y) / direction.y)


## STRAIGHT = the card's resting orientation without its dull tilt. Measured from the REAL card, not assumed from
## `tapped`: its current turn about Y minus the angle it rests at upright (`_upright_y`) is exactly the tilt to undo,
## however it got there. Applied about the board's up axis, which the cinematic shares with the Field.
func _straight_rotation(source, rest: Quaternion) -> Quaternion:
	if source == null or not is_instance_valid(source) or not (source is Card):
		return rest
	var card: Card = source
	var tilt: float = wrapf(card.rotation.y - deg_to_rad(float(card.get("_upright_y"))), -PI, PI)
	return Quaternion(Vector3.UP, -tilt) * rest


## The wind-up lean: `straight` pitched back about the card's own right axis (mirrored for the opponent's cards).
func _leaning(proxy: Card, straight: Quaternion) -> Quaternion:
	var pitch: float = deg_to_rad(-windup_pitch_degrees if proxy.controller == Card.OPPONENT else windup_pitch_degrees)
	return straight * Quaternion(Vector3.RIGHT, pitch)


## Tween `proxy` to (`to_pos`, `to_rot`) on `tween` (its transition applies). ROTATION IS SLERPED, never tweened as
## Euler angles: a card resting at a yaw of 180° reads back as +PI or -PI, and an Euler tween between the two spins it
## a full turn, which is what made the player strike rotate for no reason. The start is read when the tweener is made.
func _pose(tween: Tween, proxy: Card, to_pos: Vector3, to_rot: Quaternion, seconds: float, delay: float = 0.0) -> void:
	var from_pos: Vector3 = proxy.position
	var from_rot: Quaternion = proxy.quaternion
	tween.tween_method(func(w: float) -> void:
		if is_instance_valid(proxy):
			proxy.position = from_pos.lerp(to_pos, w)
			proxy.quaternion = from_rot.slerp(to_rot, w),
		0.0, 1.0, seconds).set_delay(delay)


## Move every [proxy, position, rotation] together and wait. A card already there is skipped, and nothing to move is
## no wait at all: an untapped card does not sit through an empty straighten beat.
func _run(moves: Array, seconds: float, trans: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	var tween: Tween = null
	for move in moves:
		var proxy: Card = move[0]
		if proxy == null or not is_instance_valid(proxy):
			continue
		if proxy.position.is_equal_approx(move[1]) and proxy.quaternion.angle_to(move[2]) < 0.001:
			continue
		if tween == null:
			tween = create_tween().set_parallel(true)
			tween.set_trans(trans).set_ease(ease_type)
		_pose(tween, proxy, move[1], move[2], seconds)
	if tween != null:
		await tween.finished


func _windup_scale(strength: float) -> float:
	return lerpf(windup_scale_range.x, windup_scale_range.y, strength)


func _charge_time(strength: float) -> float:
	return charge_seconds * lerpf(charge_scale_range.x, charge_scale_range.y, strength)


func _start_recovery(proxy: Card, start_pos: Vector3, rot: Quaternion, base_scale: Vector3 = Vector3.ZERO) -> Tween:
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pose(tween, proxy, start_pos, rot, recovery_seconds)
	if base_scale != Vector3.ZERO:
		tween.tween_property(proxy, "scale", base_scale, recovery_seconds)
	return tween


## `hit_by` is the winner's strength 0..1: a stronger blow throws the loser further and higher.
func _start_defeat(proxy: Card, direction: Vector3, hit_by: float = 0.5) -> void:
	var force := lerpf(knockback_scale_range.x, knockback_scale_range.y, hit_by)
	var spin_axis: Vector3 = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)).normalized()
	if spin_axis.length_squared() < 0.0001:
		spin_axis = Vector3.RIGHT
	_defeated[proxy] = {
		"age": 0.0,
		"velocity": (direction * knockback_speed + Vector3.UP * upward_impulse) * force,
		"spin": spin_axis * deg_to_rad(tumble_speed * _rng.randf_range(0.75, 1.2) * sqrt(force)),
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


func _shake_camera(strength: float = 0.5) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var amount := camera_shake_strength * lerpf(0.75, 1.5, strength)
	var base: Vector3 = _camera_home.origin
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for _i in range(6):
		var offset := Vector3(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0)) * amount
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
		_attacker.set_hidden(_was_hidden_a and not _survives_a)
		if _survives_a and _attacker.is_drawn_on_field():
			_attacker.global_transform = _snap_a
	if _defender != null and is_instance_valid(_defender):
		_defender.set_hidden(_was_hidden_b and not _survives_b)
		if _survives_b and _defender.is_drawn_on_field():
			_defender.global_transform = _snap_b
	for entry in _strikers:
		if entry.proxy != null and is_instance_valid(entry.proxy):
			entry.proxy.queue_free()
		var card: Card = entry.card if entry.card != null and is_instance_valid(entry.card) else null
		if card != null:
			card.set_hidden(entry.hidden)
			if card.is_drawn_on_field():
				card.global_transform = entry.snap
	_strikers.clear()
	if _camera != null and is_instance_valid(_camera):
		_camera.global_transform = _camera_home
	_camera = null
	_running = false
	finished.emit()
