extends Node3D
class_name PaymentOrb
## One of the orbs a shattered crystal leaves behind: it flies to the card being paid for and vanishes behind it.
##
## THE CURVE IS THE TARGETING ARC INVERTED. The targeting arrow rises off the source card and comes down onto its
## target; this leaves the crystal low and arrives at the card from below, so the bow points the other way. One
## quadratic Bézier — start, control, end — with the control at the chord's midpoint pushed along the bow axis. A
## negative peak bows downward, which is what makes this the targeting shape flipped.
##
## IT ENDS BEHIND THE CARD, which is the point of the whole effect: the orb is not supposed to arrive and sit there, it
## is supposed to be *swallowed*. So the destination is the card's centre pushed a little further from the camera,
## where the card's own geometry hides it. The random offset keeps a row of orbs from stacking into one blob.
##
## THE FLIGHT IS DRIVEN FROM _process, NOT A TWEEN. The first version used a Tween calling a curve sample, which
## appeared to do nothing at all — the orbs spawned and were gone again with no travel. A curve flight is not a
## property interpolation, and this way there is no callback, no baked curve and no tween lifetime to go wrong: it is
## an elapsed timer and a Bézier evaluated every frame.
##
## SIZE: the orb is deliberately small. It comes out of a crystal and has to be able to fit inside one, so the whole
## sphere is a fraction of the crystal's ~0.26 m height. `orb_radius` drives the halo size, the light range and the
## trail, so they all scale down with it.

const ORB_SCENE := preload("res://light_orb.tscn")

## Seconds from launch to arrival.
@export var duration: float = 0.8

## How far the arc bows, as a multiple of the distance to the target. NEGATIVE bows downward — this is the targeting
## curve inverted. A positive value here would be the targeting arrow's shape.
@export var peak_ratio: float = -0.55

## Random offset added to the arrival point, in metres. Keeps several orbs from converging on the same spot.
@export var arrival_noise: float = 0.16

## How far past the card the orb ends, measured away from the camera, in metres. Has to clear the card's own geometry
## for the orb to actually disappear.
@export var behind_depth: float = 0.35

## Diameter of the orb, in metres. Small on purpose: about a third of the crystal's height, so it reads as something
## that came out of the crystal rather than a ball arriving from elsewhere.
@export var orb_diameter: float = 0.09

var _orb: Node3D = null
var _from: Vector3 = Vector3.ZERO
var _control: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _flying: bool = false
## Kept so the card can be told it has been hit, at the moment the orb arrives.
var _card: Card = null

## Flies an orb of `colour` from `from` to `card`, then removes itself.
func launch(from: Vector3, colour: Color, card: Card) -> void:
	if card == null:
		queue_free()
		return
	_orb = ORB_SCENE.instantiate()
	add_child(_orb)
	_orb.set("orb_radius", orb_diameter * 0.5)
	_orb.set("orb_color", colour)
	_from = from
	_to = _destination_for(card)
	_build_arc()
	_orb.global_position = _from
	_flying = true
	_card = card
	print("[PaymentOrb] launched from %s to %s (span %.2f m, %.2f s)"
		% [_from, _to, _from.distance_to(_to), duration])

## Walks the arc. See the note above on why this is not a Tween.
func _process(delta: float) -> void:
	if not _flying:
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / maxf(duration, 0.001), 0.0, 1.0)
	if _orb != null and is_instance_valid(_orb):
		_orb.global_position = _arc_point(t)
		# Shrink to nothing over the last quarter, so the orb is *swallowed* rather than blinking out the instant it
		# touches the card. The halo is a child, so it shrinks with the core — which is what stops a wide additive
		# skirt from hanging over the card's face at the end of the flight.
		_orb.scale = Vector3.ONE * (1.0 - smoothstep(0.75, 1.0, t))
	if t >= 1.0:
		_flying = false
		# THE IMPACT. The orb has been shrinking since t = 0.75, so this fires at the moment it is already gone: the
		# card reacts to something that is no longer there, which is what makes it read as having been ABSORBED rather
		# than as a collision with a visible object.
		if _card != null and is_instance_valid(_card) and _orb != null:
			# The orb is the source of truth for its own colour, so there is no second copy to keep in step.
			var lit: Color = _orb.get("orb_color")
			# And where it was when it vanished: the shockwave starts there, projected onto the card's plane by the
			# card itself, rather than at the card's centre.
			_card.absorb_power(lit, _orb.global_position)
		print("[PaymentOrb] arrived behind the card after %.2f s" % _elapsed)
		queue_free()

## A quadratic Bézier: start, control, end.
##
## THE BOW IS FLATTENED IN Y and the whole arc is capped there. The orb must never climb above the card it is flying
## into: with a camera looking almost straight down, "higher" reads as "further up the screen", so an orb that
## overshoots upward crosses the card's face on its way in instead of sliding behind it.
func _build_arc() -> void:
	var span: float = _from.distance_to(_to)
	var bow: Vector3 = _bow_axis()
	# No vertical component in the bow: the arc may swing across the board, but it must not rise.
	bow.y = 0.0
	if bow.length_squared() < 0.0001:
		bow = Vector3.FORWARD
	bow = bow.normalized()
	_control = (_from + _to) * 0.5 + bow * (peak_ratio * span)
	# The Y cap lives in _arc_point(), not here: the crystal sits above the board so the arc still falls to the card,
	# it just cannot arch back up over it.

func _arc_point(t: float) -> Vector3:
	var u: float = 1.0 - t
	var point: Vector3 = _from * (u * u) + _control * (2.0 * u * t) + _to * (t * t)
	# The cap is the orb's OWN starting height: it may fall towards the card, but it must never climb above where it
	# came from. Capping at the card's height instead would flatten the entire flight — the crystal row sits above the
	# board, so min(from.y, to.y) IS the card's level and the orb would drop to it on the first frame and glide in
	# horizontally. Belt and braces too: with the bow already flat in Y, only a later change to peak_ratio, to the
	# arrival noise or to the bow axis could raise the path, and this catches all of them.
	point.y = minf(point.y, _from.y)
	return point

## The card's centre, jittered, then pushed away from the camera so the card hides the orb.
func _destination_for(card: Card) -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var spot: Vector3 = card.global_position
	# No jitter ABOVE the card's centre: that is the one direction the orb must not arrive from.
	spot += Vector3(randf_range(-arrival_noise, arrival_noise),
			0.0,
			randf_range(-arrival_noise, arrival_noise))
	if cam != null:
		# Away from the camera, not along the card's normal: what matters is that the orb ends up on the far side of
		# the card from the viewer, and the card faces the viewer rather than the world. On this board that also pushes
		# it downward, since the camera is looking down.
		spot += (card.global_position - cam.global_position).normalized() * behind_depth
	return spot

## The direction the arc bows in: screen-up, flattened into the camera's view plane, so the arc reads as an arc from
## the camera's point of view wherever the two cards are. A world-Y bow would be foreshortened to nothing by a camera
## looking almost straight down.
func _bow_axis() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.UP
	var up: Vector3 = -cam.global_transform.basis.y
	up -= cam.global_transform.basis.z * up.dot(cam.global_transform.basis.z)
	if up.length_squared() < 0.0001:
		return Vector3.UP
	return up.normalized()
