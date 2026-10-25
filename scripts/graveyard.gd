extends Node3D
## The Graveyard / Break Zone pile.
##
## It is a STACK: the most recent card lies on top of the pile and the older ones
## are tucked underneath. Every card in it is presented as a plain, untilted card
## with no field readout, which is what Card.enter_zone() guarantees — without it
## a card arriving from the field keeps the field's scale, its rotation and its
## power/accumulated-damage readout.
var card_offset = Vector3(0, 0.005, 0)
var randomness_range = Vector3(0.015, 0.005, 0.015)
@export var graveyard_cards = []
## Which zone a card is in once it lands here. The Break Zone and "removed from the game" are the same KIND of pile
## but not the same place, and the difference matters: a card removed from the game must not be findable by anything
## that looks in the Break Zone. Defaults to GRAVEYARD so the existing nodes keep working untouched.
@export var zone: Card.Zone = Card.Zone.GRAVEYARD

## MILL ANIMATION — lift the top card off the deck and arc it onto the pile.
##
## One card per call and each call is awaitable, so "mill 3" runs three of these one after another instead of three
## cards moving at once. That is deliberate: the milled cards should read as a sequence.
## Doubled once already (0.5 -> 1.0) after seeing it in play.
@export var mill_seconds: float = 1.0
## How far the arc rises above the MIDPOINT of the two centres, in metres. The camera is nearly top-down, so most of
## this reads as a lift toward the viewer with a little screen travel. Doubled once already (0.45 -> 0.9).
@export var mill_arc_height: float = 0.9
@export var mill_ease: Tween.EaseType = Tween.EASE_IN_OUT

## DISCARD ANIMATION — a card leaves a hand and travels to the top of this pile. Unlike draw(), the card enters the
## pile's list IMMEDIATELY (so rules/tests see the discard at once); only the visual position is tweened.
@export var discard_seconds: float = 0.35
@export var discard_arc_height: float = 0.35
@export var discard_ease: Tween.EaseType = Tween.EASE_OUT

## Animate `card` (still parented to the Deck) into the pile, then add it.
##
## The card is moved into THIS node's frame FIRST, keeping its world position, so the face-up / standard-size look of
## the Break Zone applies for the whole flight rather than popping in on landing.
func draw(card: Card) -> void:
	if card == null or not is_instance_valid(card):
		return
	var start: Vector3 = card.global_position
	if card.get_parent() != self:
		card.reparent(self, false)
		card.global_position = start
	card.enter_zone(zone)

	# Where the card will land: the same slot update_card_positions() will give it, in this node's own space.
	var index: int = graveyard_cards.size()
	var destination: Vector3 = global_transform * (card_offset * index)
	# Quadratic Bezier through a control point above the midpoint — the parabola the eye reads as "lifted and carried".
	var peak: Vector3 = (start + destination) * 0.5 + Vector3.UP * mill_arc_height

	var t: Tween = create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(mill_ease)
	t.tween_method(func(k: float) -> void:
		# De Casteljau: two lerps along the two control legs, then one between them.
		card.global_position = start.lerp(peak, k).lerp(peak.lerp(destination, k), k)
	, 0.0, 1.0, mill_seconds)
	await t.finished
	add_card(card)
		
## Discard from a hand. The card joins the pile at once and the tween moves its visual from wherever it was to
## the slot the pile already gave it. That ordering matters: discard effects, S costs and AI choices all proceed
## immediately, while the player still sees the card travel instead of teleporting.
func discard(card: Card) -> void:
	if card == null or not is_instance_valid(card):
		return
	var start: Vector3 = card.global_position
	if card.get_parent() != self:
		card.reparent(self, false)
		card.global_position = start
	graveyard_cards.append(card)
	card.broken = false
	card.enter_zone(zone)
	update_card_positions()
	var destination: Vector3 = card.global_position
	card.global_position = start
	var peak: Vector3 = (start + destination) * 0.5 + Vector3.UP * discard_arc_height
	var t: Tween = create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(discard_ease)
	t.tween_method(func(k: float) -> void:
		card.global_position = start.lerp(peak, k).lerp(peak.lerp(destination, k), k)
	, 0.0, 1.0, discard_seconds)


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

## Lay the pile out, newest on top.
##
## Positions are ABSOLUTE: the old version did `position += ...`, so every extra
## call drifted the pile further away. The scatter is derived from the card's
## index instead of a live RNG, so re-laying out (which happens whenever a card is
## added) cannot make the whole pile jitter — and the top card is kept un-scattered
## so the pile always reads as sitting on its anchor.
func update_card_positions():
	var rng := RandomNumberGenerator.new()
	for i in range(graveyard_cards.size()):
		var card = graveyard_cards[i]
		var is_top: bool = i == graveyard_cards.size() - 1
		var scatter := Vector3.ZERO
		if not is_top:
			rng.seed = i * 7919
			scatter = Vector3(
				rng.randf_range(-randomness_range.x, randomness_range.x),
				0.0,
				rng.randf_range(-randomness_range.z, randomness_range.z)
			)
		card.position = card_offset * i + scatter
