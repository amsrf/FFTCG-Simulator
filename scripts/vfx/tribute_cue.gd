extends "res://scripts/vfx/vfx_cue.gd"
## TRIBUTE (VfxEvent.Kind.TRIBUTE): an EFFECT put a card from the field into the Break Zone without breaking it
## (Game.put_card_into_graveyard -> Vfx.tributed). After ~/Desktop/Clips/tribute frames 23-37:
##   1. CHARGE - a warm orb gathers on the card with a thin vertical streak through it; the card sinks a little.
##   2. POP    - a white bloom bursts out of the orb and the card LEAVES: it rises straight up first, clear of every
##               card on the board and of the pile's own height, travels across at that height and drops straight
##               down onto its slot in the pile. Rising before travelling is what keeps it from sliding through the
##               neighbouring cards (the board camera is almost top-down, so a flat glide would cut across them).
##   3. RING   - the bloom shrinks to a hot core inside a ring that expands outward.
##   4. BREAK  - the ring tears into separate arc slashes that keep travelling and fade, with sparkles.
## The burst stays on the slot the card left; only the card travels. The real card is already in the pile, hidden;
## it is shown the moment the stand-in lands (Vfx.release_hold). sample(t) is deterministic, so a demo can freeze any
## moment.

const BURST_SHADER := preload("res://shaders/tribute_burst.gdshader")

const CHARGE_SECONDS := 0.24
## The card leaves at the pop.
const LAUNCH_AT := 0.24
const FLIGHT_SECONDS := 0.80
const BLOOM_PEAK_AT := 0.34
const RING_START := 0.30
## The arcs linger past the card's landing (~1.04 s) so they can fade out over time instead of vanishing.
const FX_END := 1.35
## The quad's half-size and the ring's widest radius, in card heights.
const HALF_EXTENT := 1.4
const RING_MAX := 0.95
## How far past RING_MAX the arcs keep travelling, and their half-width at birth (card heights): very thick.
const ARC_TRAVEL := 0.18
const ARC_BIRTH_WIDTH := 0.15
## How far above BOTH the slot and the pile the card travels, in metres. The pile sits 0.5 m above the board.
const CLEARANCE := 0.7
## The sink while it charges (frame 25 shows the card a little smaller under the orb).
const CHARGE_SINK := 0.06
## The lift's extra size, at mid-flight, so the rise reads under an orthographic camera (height alone does not).
const FLIGHT_SWELL := 0.12
## A roll about the travel direction while it flies, radians at mid-flight.
const FLIGHT_ROLL := 0.35
const RENDER_PRIORITY := 30
## PLAYBACK SPEED. Every timing above is an AUTHORED time; the cue plays them SPEED times faster, so the whole
## animation keeps its proportions and this is the one knob for "faster / slower". Real length = FX_END / SPEED
## (1.35 / 1.8 = 0.75 s; the card lands at ~0.58 s).
const SPEED := 1.8

var _card: Card = null
var _visual: Dictionary = {}
var _stand_in: Card = null
## Where the card lands: normally the real card (hidden in its pile slot). A demo can supply any Node3D.
var destination: Node3D = null
var _home := Transform3D.IDENTITY
var _height := 0.6
var _quad: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _landed := false
var _seed := 0.0
## Probe hook: the highest the card's centre has been, and the landing transform it was handed.
var peak_height := -INF
var landed_transform := Transform3D.IDENTITY


func play(event: VfxEvent) -> void:
	for target in event.targets:
		if is_instance_valid(target):
			_card = target
			break
	if _card != null:
		_visual = event.target_visuals.get(_card.get_instance_id(), {})
	_stand_in = _visual.get("stand_in", null)
	if not is_instance_valid(_stand_in):
		await get_tree().process_frame
		return
	if destination == null:
		destination = _card
	_seed = float(event.seed % 997) if event.seed != 0 else 3.0
	setup()
	var t := 0.0
	while t < FX_END:
		if not _landed and not is_instance_valid(_stand_in):
			break
		sample(t)
		await get_tree().process_frame
		t += get_process_delta_time() * SPEED
	sample(FX_END)
	_finish()


## Build the burst quad. Called by play(); a demo may call it with its own stand-in.
func setup(stand_in: Card = null) -> void:
	if stand_in != null:
		_stand_in = stand_in
	_home = _stand_in.global_transform
	_height = _stand_in._card_face_size().y * _home.basis.z.length()
	_mat = ShaderMaterial.new()
	_mat.shader = BURST_SHADER
	_mat.render_priority = RENDER_PRIORITY
	_mat.set_shader_parameter("half_extent", HALF_EXTENT)
	_mat.set_shader_parameter("seed", _seed)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * HALF_EXTENT * 2.0 * _height
	_quad = MeshInstance3D.new()
	_quad.name = "TributeBurst"
	_quad.mesh = quad
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 2.0
	add_child(_quad)
	var cam := _camera_basis()
	# Lifted toward the camera so the board can never cut the quad (it ignores depth anyway; this keeps sorting sane).
	_quad.global_transform = Transform3D(cam, _home.origin + cam.z * 0.3)


## The whole effect at `t` seconds.
func sample(t: float) -> void:
	_sample_burst(t)
	_sample_flight(t)


func _sample_burst(t: float) -> void:
	if _mat == null:
		return
	var charge := smoothstep(0.0, CHARGE_SECONDS, t)
	var after := clampf((t - LAUNCH_AT) / (FX_END - LAUNCH_AT), 0.0, 1.0)
	# The orb grows while it charges, then the core it leaves behind fades with the ring.
	var core_r := lerpf(0.06, 0.26, charge * charge) - 0.06 * after
	var core_i := lerpf(0.0, 1.3, charge) * (1.0 - smoothstep(0.62, 1.05, t))
	# The streak brightens late in the charge and is cut by the pop.
	var beam := smoothstep(0.05, CHARGE_SECONDS, t) * (1.0 - smoothstep(LAUNCH_AT, LAUNCH_AT + 0.06, t))
	# Bloom: pops out fast, then fades.
	var pop := smoothstep(LAUNCH_AT - 0.02, BLOOM_PEAK_AT, t)
	var bloom_r := lerpf(0.22, 0.62, 1.0 - pow(1.0 - pop, 3.0))
	var bloom_i := pop * (1.0 - smoothstep(BLOOM_PEAK_AT, BLOOM_PEAK_AT + 0.2, t)) * 1.2
	# Arcs: born THICK at the pop, travel outward the whole time (fast first, easing out) and thin as they go; the
	# shader turns ring_life into each arc's thickness. Only a short overall fade guards the very end.
	var life := clampf((t - RING_START) / (FX_END - 0.05 - RING_START), 0.0, 1.0)
	var ring_r := lerpf(0.38, RING_MAX + ARC_TRAVEL, 1.0 - pow(1.0 - life, 2.2))
	var ring_i := smoothstep(RING_START, RING_START + 0.05, t) * (1.0 - smoothstep(FX_END - 0.08, FX_END, t))
	var ring_w := ARC_BIRTH_WIDTH
	var sparkle := smoothstep(0.38, 0.50, t) * (1.0 - smoothstep(0.95, FX_END, t))
	_mat.set_shader_parameter("time", t)
	_mat.set_shader_parameter("core_radius", core_r)
	_mat.set_shader_parameter("core_intensity", core_i)
	_mat.set_shader_parameter("beam", beam)
	_mat.set_shader_parameter("bloom_radius", bloom_r)
	_mat.set_shader_parameter("bloom_intensity", bloom_i)
	_mat.set_shader_parameter("ring_radius", ring_r)
	_mat.set_shader_parameter("ring_width", ring_w)
	_mat.set_shader_parameter("ring_intensity", ring_i)
	_mat.set_shader_parameter("ring_life", life)
	_mat.set_shader_parameter("sparkle", sparkle)


func _sample_flight(t: float) -> void:
	if _landed or not is_instance_valid(_stand_in):
		return
	if t < LAUNCH_AT:
		# CHARGE: it sinks a little under the orb.
		var sink := 1.0 - CHARGE_SINK * smoothstep(0.0, CHARGE_SECONDS, t)
		_stand_in.global_transform = Transform3D(_home.basis.scaled_local(Vector3.ONE * sink), _home.origin)
		_note_height()
		return
	var target: Transform3D = destination.global_transform if is_instance_valid(destination) else _home
	var u := clampf((t - LAUNCH_AT) / FLIGHT_SECONDS, 0.0, 1.0)
	var start := _home.origin
	var finish := target.origin
	var peak_y := maxf(start.y, finish.y) + CLEARANCE
	# RISE, TRAVEL, DROP: the vertical move happens at the two ends, the sideways move only in the middle, so the
	# card is already above everything before it moves across and does not come down until it is over the pile.
	var up := smoothstep(0.0, 0.24, u)
	var down := smoothstep(0.78, 1.0, u)
	var across := smoothstep(0.16, 0.84, u)
	var y := lerpf(lerpf(start.y, peak_y, up), finish.y, down)
	var pos := Vector3(lerpf(start.x, finish.x, across), y, lerpf(start.z, finish.z, across))
	# Orientation and size blend from the field slot to the pile slot; a swell and a roll ride on top mid-flight.
	var turn := smoothstep(0.1, 0.9, u)
	var rot: Quaternion = _home.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), turn)
	var size: Vector3 = _home.basis.get_scale().lerp(target.basis.get_scale(), across)
	size *= (1.0 - CHARGE_SINK) * (1.0 - across) + across
	size *= 1.0 + FLIGHT_SWELL * sin(PI * u)
	var travel := Vector3(finish.x - start.x, 0.0, finish.z - start.z)
	var roll_axis := travel.normalized() if travel.length() > 0.001 else Vector3.RIGHT
	var pose := Basis(roll_axis, FLIGHT_ROLL * sin(PI * u)) * Basis(rot)
	_stand_in.global_transform = Transform3D(pose.scaled_local(size), pos)
	_note_height()
	if u >= 1.0:
		_land(target)


func _note_height() -> void:
	peak_height = maxf(peak_height, _stand_in.global_position.y)


## Landed: the stand-in goes and the real card shows in the pile.
func _land(target: Transform3D) -> void:
	_landed = true
	landed_transform = target
	if _card != null:
		Vfx.release_hold(_card, _visual, false)
	elif is_instance_valid(_stand_in):
		_stand_in.global_transform = target


func _finish() -> void:
	if not _landed and _card != null:
		Vfx.release_hold(_card, _visual, false)
	if is_instance_valid(_quad):
		_quad.queue_free()


func _camera_basis() -> Basis:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_transform.basis.orthonormalized()
	return Basis.IDENTITY
