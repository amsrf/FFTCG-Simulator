extends RefCounted
## The card's "something was absorbed into this" reaction: a soft radial flash on the card's face, an expanding shockwave
## ring across it, and a punch (a brief swell of the card's own scale).
##
## EXTRACTED FROM Card, which had grown to hold a card model, its zone presentation, the glow ring AND this. This was the
## piece with a single entry point (`play`) and a single outside caller (payment_orb), so it was the cleanest thing in
## there to separate — no test reaches into it and no other file calls it.
##
## OWNERSHIP, which is the whole point of the split:
##   * THIS owns the two quads and their tweens;
##   * the CARD owns the knobs (`absorb_seconds`/`absorb_punch` are @exported THERE, so they stay tunable in the
##     Inspector — that is how the punch was tuned) and it owns the glow that outlives the reaction, because that glow is
##     not a reaction at all: it is the ring's lowest-priority meaning.
##
## Deliberately no `class_name`: a new global class is not in Godot's class cache until the editor rescans, and every
## reference to one from a script that loads headless has bitten this project. `card.gd` preloads the path instead.

const HALO := preload("res://shaders/orb_halo.gdshader")
const RING := preload("res://shaders/absorb_ring.gdshader")

## The node the quads are added to, whose local space the impact point is projected into, and whose scale is punched.
var card: Node3D = null
## Whole reaction length in seconds. Mirrored from Card.absorb_seconds each time it plays.
var seconds: float = 0.25
## Peak swell, as a multiple of the resting scale. Mirrored from Card.absorb_punch.
var punch: float = 1.15
## Kept so the Inspector knob still exists on the card. The ring's travel is derived from the card's own width.
var ring_size: float = 1.9
var _tween: Tween = null
## The scale to come back to. Recorded only on the FIRST hit of a volley — see play().
var _resting: Vector3 = Vector3.ONE

func _init(card_ref: Node3D) -> void:
	card = card_ref

## `colour` is the mana's colour, `at` the impact point in WORLD space (where the orb vanished), and `face` the card's
## face size in metres — passed in rather than read from the card, because measuring the mesh is the card's business.
## A zero `at` means none was supplied and the ring falls back to the middle.
func play(colour: Color, at: Vector3 = Vector3.ZERO, face: Vector2 = Vector2(0.4, 0.6)) -> void:
	if card == null or not card.is_inside_tree():
		return
	_flash(colour, face)
	_shockwave(colour, at, face)
	# A VOLLEY MUST NOT RATCHET. The row sends one orb per crystal, roughly 0.1 s apart, so a later orb arrives while an
	# earlier punch is still up. Reading `scale` on every hit recorded the INFLATED size as the resting size, so the card
	# grew a little with every orb and never came back — a permanent size increase. Only the first hit of a volley records
	# the real resting scale; every later hit reuses it.
	if _tween == null or not _tween.is_valid():
		_resting = card.scale
	else:
		_tween.kill()
	_tween = card.create_tween()
	# Back-out on the way up gives the punch its snap. A plain ease reads as a gentle swell instead of a hit.
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(card, "scale", _resting * punch, seconds * 0.35)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(card, "scale", _resting, seconds * 0.65)
	# Snap on completion: belt and braces against the same class of drift arriving from anywhere else, including this
	# tween being killed halfway through by a zone change.
	_tween.tween_callback(func(): card.scale = _resting)

## An expanding ring in the orb's colour, thrown outward across the card's face.
##
## This is the loudest of the three cues and the most legible from a distance: the flash says something happened, the
## punch says the card felt it, and the ring says it is SPREADING. Radius and brightness are tweened together so the ring
## both travels and spends itself.
func _shockwave(colour: Color, at: Vector3, face: Vector2) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = RING
	mat.set_shader_parameter("ring_color", colour)
	mat.set_shader_parameter("intensity", 2.0)
	mat.set_shader_parameter("ring_radius", 0.05)
	# A SQUARE quad covering the card's longer side, plus a rounded-rect mask in the shader. A quad cut to the card's
	# shape would make the ring an ellipse AND clip it along straight edges — visibly wrong at the card's rounded corners,
	# which is exactly what "must not go beyond the card" rules out.
	var side: float = maxf(face.x, face.y)
	mat.set_shader_parameter("card_half", face * 0.5)
	var plane := PlaneMesh.new()
	plane.size = Vector2(side, side)
	var quad := MeshInstance3D.new()
	quad.name = "AbsorbRing"
	quad.mesh = plane
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ORIGIN = THE IMPACT POINT. The caller projects the orb's last position onto the card's plane; in the card's local
	# space that is just (x, 0, z), because local Y is the card's normal.
	if at != Vector3.ZERO:
		var here: Vector3 = card.to_local(at)
		quad.position = Vector3(here.x, 0.0, here.z)
	card.add_child(quad)
	var tween := card.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mat, "shader_parameter/ring_radius", side * 0.5, seconds)
	tween.tween_property(mat, "shader_parameter/intensity", 0.0, seconds)
	tween.chain().tween_callback(quad.queue_free)

## A soft radial burst in the orb's colour, lying flat on the card's own face.
func _flash(colour: Color, face: Vector2) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = HALO
	mat.set_shader_parameter("halo_color", colour)
	mat.set_shader_parameter("intensity", 2.4)
	# Tighter than the orb's own halo: a card is broader than it is tall, so the default skirt would spill off it.
	mat.set_shader_parameter("falloff", 1.6)
	var plane := PlaneMesh.new()
	# A PlaneMesh already lies in the XZ plane, which is the plane the cards lie in, so no rotation is needed: as a child
	# it inherits the card's own tilt and fan rotation.
	plane.size = face * 1.3
	var quad := MeshInstance3D.new()
	quad.name = "AbsorbFlash"
	quad.mesh = plane
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	card.add_child(quad)
	var tween := card.create_tween()
	tween.tween_property(mat, "shader_parameter/intensity", 0.0, seconds)
	tween.tween_callback(quad.queue_free)
