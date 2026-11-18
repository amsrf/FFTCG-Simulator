extends Node3D
## The Graveyard / Break Zone pile - and, with `zone = REMOVED`, the pile of cards removed from the game.
##
## RULES: `graveyard_cards` is the pile, newest last. PRESENTATION: the pile is drawn as a PIT (scripts/game/pit.gd,
## blue for the Break Zone, purple for Removed) and a card in it is HIDDEN, because it has gone into the pit. Cards
## still enter the zone through Card.enter_zone() (face up, pile size, no field readout), so a card that comes back
## out (returned to hand, played from the Break Zone) starts from a clean look.
@export var graveyard_cards = []
## Which zone a card is in once it lands here. The Break Zone and "removed from the game" are the same KIND of pile
## but not the same place, and the difference matters: a card removed from the game must not be findable by anything
## that looks in the Break Zone. Defaults to GRAVEYARD so the existing nodes keep working untouched.
@export var zone: Card.Zone = Card.Zone.GRAVEYARD

## MILL / DISCARD — the card is PULLED INTO THE PIT (~/Desktop/Clips/pits frames 62-107): it flies from where it
## was to a point above the pit's mouth, hovers there shrinking a little, washes out to white, then turns edge-on and
## sinks through the mouth while it shrinks (the opaque pit top clips it, which is what reads as "pulled in"), and the
## pit flares. A card in the pit is HIDDEN: the rules list still holds it, and the pit's click opens the zone view.
##
## Mill is one card per call and each call is awaitable, so "mill 3" runs three of these one after another.
## Doubled once already (0.5 -> 1.0) after seeing it in play. It is the WHOLE intake (flight + hover + sink).
@export var mill_seconds: float = 1.0
## How far the flight's arc rises above the MIDPOINT of its two ends, in metres.
@export var mill_arc_height: float = 0.9
## A discard's FLIGHT (hand -> above the pit); the hover and the sink come on top of it.
@export var discard_seconds: float = 0.55
@export var discard_arc_height: float = 0.35
## Several cards discarded together leave one after another by this much, so they do not fall in as one.
@export var discard_stagger: float = 0.09
## The pit's mouth: how high above the pit the card hovers before it goes in (metres), and for how long.
@export var intake_hover_height: float = 0.7
@export var intake_hover_seconds: float = 0.16
## The fall through the mouth (turn edge-on + sink + shrink).
@export var intake_sink_seconds: float = 0.22
## Size while hovering (it shrinks to this) and at the bottom of the sink, as fractions of the pile size.
@export var intake_hover_shrink: float = 0.86
@export var intake_end_scale: float = 0.3
## How far the card turns toward edge-on while it sinks (radians; PI/2 would be fully edge-on).
@export var intake_turn: float = deg_to_rad(76.0)
## A FACE-DOWN card discarded from a hand (the opponent's) is shown first: it comes toward the camera and down the
## screen out of the hand (metres), grows, YAWS about its long axis to turn face-up (the art is swapped in while it is
## edge-on), and is held long enough to read before it flies to the pit.
@export var discard_reveal_lift: float = 0.6
@export var discard_reveal_drop: float = 0.45
@export var discard_reveal_scale: float = 1.35
@export var discard_reveal_flip_seconds: float = 0.24
@export var discard_reveal_hold_seconds: float = 0.4
## Several face-down cards discarded together ("discard 2"): each starts its flip this long after the previous one,
## and they are held SIDE BY SIDE across the screen, `discard_reveal_spacing` card widths apart, so none hides another.
@export var discard_reveal_stagger: float = 0.12
@export var discard_reveal_spacing: float = 1.08

const PIT := preload("res://scripts/game/pit.gd")
## The pit's outer radius in metres (game.tscn sets the Removed piles smaller than the Break Zone ones).
@export var pit_radius: float = 0.21
## Where a card rests: the pit's centre, below the top of the drum (so it is inside the pit even if shown).
const REST_LOCAL := Vector3.ZERO

var pit: Node3D = null
## Cards whose intake is still playing: update_card_positions() leaves them alone.
var _in_flight: Dictionary = {}


func _ready() -> void:
	pit = PIT.new()
	pit.name = "Pit"
	add_child(pit)
	pit.setup(zone == Card.Zone.REMOVED, pit_radius)
	pit.clicked.connect(_open_zone_view)


## A milled card: in the pile at once for the rules, pulled into the pit when the presentation queue reaches it.
func draw(card: Card) -> void:
	if card == null or not is_instance_valid(card):
		return
	# RULES, at once: the milled card is in the pile from this moment. It came from the deck, so no "from the field"
	# trigger can fire. Only the zone is recorded here; enter_zone() is presentation and runs with the flight.
	var start: Transform3D = card.global_transform
	graveyard_cards.append(card)
	card.current_zone = zone
	# Several mills play one after another, because the queue is serial.
	Vfx.present(func() -> void: await _swallow([{"card": card, "start": start}], _mill_flight(), mill_arc_height, 0.0))


func _mill_flight() -> float:
	return maxf(mill_seconds - intake_hover_seconds - intake_sink_seconds, 0.1)


## Discard from a hand: one card, or a whole mana payment.
##
## RULES, at once: the cards are in the pile from this moment, so discard effects, S costs and AI choices all see
## them immediately. PRESENTATION, queued: the cards fly to the pit together (one queue entry for the batch, a short
## stagger between them), so a three-card payment is one gesture rather than three in a row.
func discard(card: Card) -> void:
	discard_many([card])

func discard_many(cards: Array) -> void:
	var moves: Array = []
	for card in cards:
		if card == null or not is_instance_valid(card):
			continue
		# A discard is public: a card nobody could see (the opponent's hand) is revealed before it goes in.
		moves.append({"card": card, "start": card.global_transform, "reveal": not card.revealed})
		graveyard_cards.append(card)
		card.broken = false
		card.current_zone = zone
	if not moves.is_empty():
		Vfx.present(func() -> void:
			await _reveal_face_down(moves)
			await _swallow(moves, discard_seconds, discard_arc_height, discard_stagger))


## Turn every face-down card in `moves` face-up where it is (all together), then hold; each move's `start` becomes
## the revealed pose so the flight leaves from there. Cards already face-up are untouched, and nothing waits when
## none needs it.
func _reveal_face_down(moves: Array) -> void:
	var tweens: Array = []
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var revealing: Array = []
	for m in moves:
		if m.get("reveal", false) and is_instance_valid(m["card"]):
			revealing.append(m)
	if revealing.is_empty():
		return
	# Where each is held: out of the hand toward the camera and down the screen, then laid side by side about their
	# common centre along the screen's horizontal (one card: exactly where it came out).
	var starts: Array = []
	var centre := Vector3.ZERO
	for m in revealing:
		var card: Card = m["card"]
		# The hand's fan tween must not keep writing hand-local positions over the reveal.
		card.stop_hand_layout()
		var start: Transform3D = card.global_transform
		starts.append(start)
		var origin: Vector3 = start.origin
		if cam != null:
			origin += (cam.global_position - start.origin).normalized() * discard_reveal_lift
			origin += -cam.global_basis.y.normalized() * discard_reveal_drop
		centre += origin
	centre /= revealing.size()
	var across: Vector3 = cam.global_basis.x.normalized() if cam != null else Vector3.RIGHT
	var count: int = revealing.size()
	for i in count:
		var m: Dictionary = revealing[i]
		var card: Card = m["card"]
		var start: Transform3D = starts[i]
		var width: float = card._card_face_size().x * start.basis.get_scale().x * discard_reveal_scale
		var origin: Vector3 = centre + across * (float(i) - float(count - 1) * 0.5) * width * discard_reveal_spacing
		# UPRIGHT FOR THE VIEWER. The opponent's hand is mirrored, so the face would come out UPSIDE DOWN. The fix is a
		# half turn about the face normal, applied in the instant the card is edge-on (with the face swap), where it
		# cannot be seen: the yaw stays the only motion. The art's top is the card's local -Z.
		var landed: Basis = Basis(start.basis.get_rotation_quaternion())
		if cam != null and is_upside_down_on_screen(landed, origin, cam):
			landed = Basis(landed.y.normalized(), PI) * landed
		var shown := Transform3D(landed.scaled_local(Vector3.ONE * start.basis.get_scale().x * discard_reveal_scale),
			origin)
		m["start"] = shown
		var t: Tween = create_tween()
		if i > 0 and discard_reveal_stagger > 0.0:
			t.tween_interval(discard_reveal_stagger * i)
		var flip: float = maxf(discard_reveal_flip_seconds, 0.0001)
		t.tween_method(func(k: float) -> void: _reveal_pose(card, start, shown, k), 0.0, 1.0, flip)
		# Everyone is held until the LAST one has been shown for the full hold.
		var hold: float = discard_reveal_hold_seconds + discard_reveal_stagger * (count - 1 - i)
		if hold > 0.0:
			t.tween_interval(hold)
		tweens.append(t)
	for t in tweens:
		if t.is_valid() and t.is_running():
			await t.finished


## The first half turns from `start`, the second half arrives at `shown` (which may be `start` turned half a turn about
## its face normal, to be upright): both are edge-on at the swap, where the two poses cover the same sliver.
func _reveal_pose(card: Card, start: Transform3D, shown: Transform3D, k: float) -> void:
	if not is_instance_valid(card):
		return
	var u: float = smoothstep(0.0, 1.0, k)
	var angle: float = u * PI if u < 0.5 else (u - 1.0) * PI
	if u >= 0.5 and not card.revealed:
		card.set_revealed(true)
	var from: Basis = Basis(start.basis.get_rotation_quaternion()) if u < 0.5 \
			else Basis(shown.basis.get_rotation_quaternion())
	var long_axis: Vector3 = from.z.normalized()
	var size: float = lerpf(start.basis.get_scale().x, shown.basis.get_scale().x, u)
	var pose: Basis = (Basis(long_axis, angle) * from).scaled_local(Vector3.ONE * size)
	card.global_transform = Transform3D(pose, start.origin.lerp(shown.origin, u))

## True when a card with rotation `basis` at `origin` shows its art's top (local -Z) pointing DOWN the screen.
static func is_upside_down_on_screen(basis: Basis, origin: Vector3, cam: Camera3D) -> bool:
	var top: Vector2 = cam.unproject_position(origin - basis.z.normalized() * 0.1)
	var centre: Vector2 = cam.unproject_position(origin)
	return top.y > centre.y


## A card arriving from somewhere OTHER than the field (a revealed card removed from the game, say): it joins the
## pile at once for the rules, and is pulled in from where it is when the presentation queue reaches it. No "from the
## field" trigger can fire, so none is checked.
func receive(card: Card) -> void:
	if card == null or not is_instance_valid(card):
		return
	graveyard_cards.append(card)
	card.broken = false
	card.current_zone = zone
	Vfx.present(func() -> void:
		if not is_instance_valid(card):
			return
		await _swallow([{"card": card, "start": card.global_transform}], discard_seconds, discard_arc_height, 0.0))


## The transform a card has resting in this pile (pile orientation, pile size, at the pit's centre), in world space.
func rest_transform() -> Transform3D:
	var basis: Basis = global_transform.basis.orthonormalized().scaled_local(Vector3.ONE * Card.PILE_WORLD_SCALE)
	return Transform3D(basis, global_transform * REST_LOCAL)


## Where an arriving card hovers before it goes in: the rest pose lifted off the mouth TOWARD THE CAMERA, so that on
## screen it hangs right over the pit (lifted straight up, perspective drew it beside the pit instead).
func mouth_transform() -> Transform3D:
	var rest: Transform3D = rest_transform()
	var mouth := Vector3(rest.origin.x, pit.top_y() if pit != null else rest.origin.y, rest.origin.z)
	var lift := Vector3.UP
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		lift = (cam.global_position - mouth).normalized()
	return Transform3D(rest.basis, mouth + lift * intake_hover_height)


## Fly every card in `moves` ({card, start}) to the mouth and pull it in. Awaitable; ends when the last card is in.
func _swallow(moves: Array, flight: float, arc: float, stagger: float) -> void:
	var tweens: Array = []
	var order := 0
	for m in moves:
		var card: Card = m["card"]
		if not is_instance_valid(card):
			continue
		var start: Transform3D = m["start"]
		_in_flight[card] = true
		if card.get_parent() != self:
			card.reparent(self, false)
		# The pile's look for the whole flight (face up, no field readout), then back to where it started.
		card.enter_zone(zone)
		card.global_transform = start
		# A card just revealed out of a hand keeps the orientation it was shown in: it MOVES to the pit, no turn.
		tweens.append(_intake(card, start, flight, arc, stagger * order, false, bool(m.get("reveal", false))))
		order += 1
	for t in tweens:
		if t != null and t.is_valid() and t.is_running():
			await t.finished


## A STAND-IN that has already arrived at the mouth (the tribute cue's flight) goes in the same way and is freed.
func swallow_stand_in(stand_in: Card) -> void:
	if not is_instance_valid(stand_in):
		return
	_intake(stand_in, stand_in.global_transform, 0.0, 0.0, 0.0, true)


## One card's intake as ONE tween: flight (skipped when `flight` is 0), hover, sink, then hidden in the pit (or
## freed, for a stand-in). Returned so callers can join several.
func _intake(card: Card, start: Transform3D, flight: float, arc: float, delay: float, free_after: bool,
		keep_rotation: bool = false) -> Tween:
	var rest: Transform3D = rest_transform()
	var mouth: Transform3D = mouth_transform()
	var total: float = flight + intake_hover_seconds + intake_sink_seconds
	var t: Tween = create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_method(func(k: float) -> void: _intake_pose(card, start, mouth, rest, flight, arc, k, keep_rotation),
		0.0, total, total)
	if pit != null:
		# The flare goes off as the card drops through the mouth.
		t.parallel().tween_callback(pit.flare).set_delay(flight + intake_hover_seconds + intake_sink_seconds * 0.45)
	t.tween_callback(func() -> void: _settle(card, free_after))
	return t


## The pose at time `k` of an intake (deterministic, so a demo can freeze any moment).
## `keep_rotation`: the card keeps `start`'s orientation the whole way (a revealed discard): position and size only.
func _intake_pose(card: Card, start: Transform3D, mouth: Transform3D, rest: Transform3D, flight: float, arc: float,
		k: float, keep_rotation: bool = false) -> void:
	if not is_instance_valid(card):
		return
	var q_mouth: Quaternion = start.basis.get_rotation_quaternion() if keep_rotation \
			else mouth.basis.get_rotation_quaternion()
	var s_mouth: float = mouth.basis.get_scale().x
	var white := 0.0
	var pose: Basis
	var pos: Vector3
	if k < flight:
		# FLIGHT: a quadratic Bezier through a point above the midpoint; the card turns and resizes to the pile's.
		var u: float = ease(k / flight, -1.6)
		var peak: Vector3 = (start.origin + mouth.origin) * 0.5 + Vector3.UP * arc
		pos = start.origin.lerp(peak, u).lerp(peak.lerp(mouth.origin, u), u)
		var q: Quaternion = start.basis.get_rotation_quaternion().slerp(q_mouth, smoothstep(0.0, 1.0, u))
		var s: Vector3 = start.basis.get_scale().lerp(Vector3.ONE * s_mouth, u)
		pose = Basis(q).scaled_local(s)
	else:
		var hover_end: float = flight + intake_hover_seconds
		var drift: Vector3 = (rest.origin - mouth.origin).normalized() * 0.05
		if k < hover_end:
			# HOVER: settling a little lower, shrinking, washing out to white over its second half.
			var v: float = (k - flight) / maxf(intake_hover_seconds, 0.0001)
			pos = mouth.origin + drift * v
			pose = Basis(q_mouth).scaled_local(Vector3.ONE * s_mouth * lerpf(1.0, intake_hover_shrink, v))
			white = smoothstep(0.3, 1.0, v)
		else:
			# SINK: accelerating into the pit, turning edge-on about its long axis, shrinking.
			var w: float = clampf((k - hover_end) / maxf(intake_sink_seconds, 0.0001), 0.0, 1.0)
			var e: float = w * w
			pos = (mouth.origin + drift).lerp(rest.origin, e)
			# NEARLY edge-on, turned so the white face still faces the camera: fully edge-on shows only the card's
			# dark side wall, where the reference shows a thin white sliver.
			var long_axis: Vector3 = mouth.basis.z.normalized()
			var to_camera: Vector3 = (mouth.origin - rest.origin).normalized()
			var side: float = 1.0 if (Basis(long_axis, 1.0) * mouth.basis.y.normalized()).dot(to_camera) \
					>= (Basis(long_axis, -1.0) * mouth.basis.y.normalized()).dot(to_camera) else -1.0
			var turn := Basis() if keep_rotation else Basis(long_axis, side * intake_turn * smoothstep(0.0, 0.7, w))
			var s: float = s_mouth * lerpf(intake_hover_shrink, intake_end_scale, e)
			pose = (turn * Basis(q_mouth)).scaled_local(Vector3.ONE * s)
			white = 1.0
	card.global_transform = Transform3D(pose, pos)
	_set_whiteout(card, white)


func _set_whiteout(card: Card, value: float) -> void:
	var mat: ShaderMaterial = card.get("mat") as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("whiteout", value)


## The card is in: hidden in the pit, white washed off (so it is itself again if it ever comes back out).
func _settle(card: Card, free_after: bool) -> void:
	if not is_instance_valid(card):
		return
	_set_whiteout(card, 0.0)
	if free_after:
		card.queue_free()
		return
	_in_flight.erase(card)
	if card.get_parent() == self:
		update_card_positions()


func add_card(card):
	# READ THE ORIGIN BEFORE MOVING IT. These two triggers are specifically "put FROM THE FIELD into the Break Zone",
	# so a card discarded from hand or milled from the deck must not fire them, and the pile is the only place that
	# can still see where the card came from.
	var from_field: bool = card.current_zone == Card.Zone.FIELD
	var was_broken: bool = card.broken

	graveyard_cards.append(card)
	card.reparent(self, false)
	# Normalise the look BEFORE placing it. (The old version only set position,
	# so the card kept whatever it was wearing in the zone it came from.)
	card.enter_zone(zone)
	_in_flight.erase(card)
	# A break (or any instant move) does not fly: the card is simply in the pit now. Its look is the break's business
	# (the shatter), or the tribute cue's, which pulls its stand-in into the pit.
	update_card_positions()

	# THE PILE INCITES THE CARD, once the card is IN it. That ordering is the rule: the effect is added to the stack
	# after the card has touched the Break Zone, never while it is still on the field.
	#
	# The Removed pile shares this scene, so `zone` is what separates "arrived in the Break Zone" from "exiled".
	if zone != Card.Zone.GRAVEYARD or not from_field:
		card.broken = false
		return
	card.broken = false
	var host: Node = null
	if get_parent() != null:
		host = get_parent().get_parent()
	if host != null and host.has_method("trigger_break_zone_keywords"):
		host.call("trigger_break_zone_keywords", card, was_broken)

## Lay the pile out: every card rests in the pit, HIDDEN. A card whose intake is still playing is left alone, and so
## is one the rules already put here but whose flight is still queued (it is not drawn here yet).
func update_card_positions():
	for card in graveyard_cards:
		if not is_instance_valid(card) or card.get_parent() != self or _in_flight.has(card):
			continue
		card.position = REST_LOCAL
		card.set_hidden(true)

## CARD INPUT. A card in a pile is LOOKED AT, not played: clicking one opens the same fan window the deck search
## uses, so the player can check what is in the zone. The host is two levels up (pile -> Player -> Game) and it is
## duck-typed, so a pile mounted anywhere else simply does nothing rather than erroring.
func on_card_grabbed(_card: Card) -> void:
	_open_zone_view()


func _open_zone_view() -> void:
	var host: Node = get_parent().get_parent() if get_parent() != null else null
	if host != null and host.has_method("_show_zone_view"):
		host.call("_show_zone_view", self, "Removed from the Game" if zone == Card.Zone.REMOVED else "Graveyard")
