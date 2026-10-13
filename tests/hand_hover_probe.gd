extends Node
## The hand's layout, and what a hover does to one card.
##
## Organised as the five things the hand is supposed to do, so the checks read as the spec:
##   1. it stays CENTRED and ON SCREEN horizontally at every size
##   2. at rest most of each card is BELOW the bottom edge, leaving the name-and-cost strip showing
##   3. hovering brings one card up — whole, upright, enlarged, and in front of the others
##   4. adding and removing cards RE-FANS the hand smoothly rather than snapping
##   5. the LEAN is subtle: 2 degrees per card, 12 degrees at most
##
## Item 1 runs LAST because sweeping the hand size consumes the cards, and it leaves the hand the size it found it.
##
## THE SIZE TEST IS THE ONE THAT MATTERS: a real card is put on the stack and measured, and the hovered hand card has to
## match it. Checking that two table entries agree with each other would prove nothing.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _failures: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[HandHover] ok   %s" % what)
	else:
		_failures += 1
		print("[HandHover] FAIL %s" % what)

func _finish() -> void:
	print("[HandHover] %d checks | failures: %d" % [_checks, _failures])
	print("[HandHover] RESULT: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit()

## The four face corners of `card`, in the order (-x,-y) (x,-y) (-x,y) (x,y). The face size is the mesh's, unscaled,
## so it is multiplied by the card's own transform — which already carries its scale.
func _corners(card: Card) -> Array:
	var half: Vector2 = card._card_face_size() * 0.5
	var xf: Transform3D = card.global_transform
	return [xf * Vector3(-half.x, 0.0, -half.y), xf * Vector3(half.x, 0.0, -half.y),
		xf * Vector3(-half.x, 0.0, half.y), xf * Vector3(half.x, 0.0, half.y)]

## How much of `card` is on screen, and the y of its top and bottom edges in pixels.
func _visible(card: Card, cam: Camera3D, view: Vector2) -> Dictionary:
	var top: float = INF
	var bottom: float = -INF
	var left: float = INF
	var right: float = -INF
	for corner in _corners(card):
		var p: Vector2 = cam.unproject_position(corner)
		top = minf(top, p.y)
		bottom = maxf(bottom, p.y)
		left = minf(left, p.x)
		right = maxf(right, p.x)
	return {
		"top": top, "bottom": bottom, "left": left, "right": right,
		"visible": clampf((view.y - top) / maxf(bottom - top, 0.0001), 0.0, 1.0),
	}

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	await get_tree().process_frame
	var game: Node = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var hand: Hand = game.get("hand")
	_expect(hand != null, "the match has a hand")
	if hand == null or hand.cards.size() < 3:
		_finish()
		return

	var cam: Camera3D = get_viewport().get_camera_3d()
	_expect(cam != null, "the board camera is available to check against")
	if cam == null:
		_finish()
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var px_per_metre: float = view.y / maxf(cam.size, 0.001)

	var resting: float = hand.hand_scale
	var face: Vector2 = hand.cards[0]._card_face_size()
	print("[HandHover] resting %.2f | stack %.2f | %d cards | a fan card is %.0f x %.0f px" % [
		resting, Card.STACK_CARD_SCALE, hand.cards.size(),
		face.x * resting * px_per_metre, face.y * resting * px_per_metre])
	_expect(resting < Card.STACK_CARD_SCALE,
		"the hand RESTS smaller than the stack, so a hover has somewhere to grow to")

	# ---------------------------------------------------------------- 5. the lean is subtle
	print("[HandHover] --- 5. the lean ----------------------------------------------")
	var per_card: float = rad_to_deg(absf(hand.fan_angle_for(1) - hand.fan_angle_for(0)))
	# THE MOST any one card leans, not the spread end to end. The spec caps each card at about 12 degrees off vertical,
	# and the spread is twice that — measuring the spread failed a hand that was well inside the spec.
	var max_lean: float = 0.0
	for i in range(hand.cards.size()):
		max_lean = maxf(max_lean, rad_to_deg(absf(hand.fan_angle_for(i))))
	print("[HandHover] neighbours differ by %.2f deg; the most any card leans is %.1f deg" % [per_card, max_lean])
	_expect(per_card > 0.0 and per_card <= 2.5, "each card leans at most 2.5 degrees from its neighbour")
	_expect(max_lean <= 12.5, "and no card leans more than 12 degrees off vertical")

	# ---------------------------------------------------------------- 2. at rest, most of the card is off the bottom
	print("[HandHover] --- 2. the strip left showing at rest --------------------------")
	# The MIDDLE card, because that is the one the sink is measured from and the highest of the row.
	var middle: Card = hand.cards[hand.cards.size() / 2]
	var rest_box: Dictionary = _visible(middle, cam, view)
	print("[HandHover] the middle card tops out at y %.0f of %.0f and its bottom is at y %.0f — %.0f%% visible" % [
		rest_box["top"], view.y, rest_box["bottom"], rest_box["visible"] * 100.0])
	_expect(rest_box["top"] > 0.0, "its top edge is on screen, so the name and cost can be read")
	_expect(rest_box["bottom"] > view.y, "and its bottom hangs off the bottom of the screen")
	_expect(rest_box["visible"] > 0.35 and rest_box["visible"] < 0.6,
		"leaving roughly the top 40-50% of the card showing at rest")

	# The arch: the MIDDLE highest, the ends gently lower. The DIRECTION is the part worth asserting — the row was a
	# bowl before (ends high, middle low) and a handful of pixels reads either way by eye.
	var mid_px: float = INF
	var end_px: float = -INF
	for i in range(hand.cards.size()):
		var c: Card = hand.cards[i]
		if c.get_parent() != hand:
			continue
		var cy: float = cam.unproject_position(hand.global_transform * c.position).y
		if i == hand.cards.size() / 2:
			mid_px = cy
		if i == 0 or i == hand.cards.size() - 1:
			end_px = maxf(end_px, cy)
	print("[HandHover] the middle card sits %.1f px above the ends" % (end_px - mid_px))
	_expect(end_px - mid_px > 2.0, "the row arches with the MIDDLE highest, not the ends")
	_expect(end_px - mid_px < 24.0, "and only gently")

	# ---------------------------------------------------------------- 3. the hover
	print("[HandHover] --- 3. the hover ---------------------------------------------")
	var card: Card = hand.cards[1]
	# READ, DO NOT FIX UP. This check caught a real bug precisely because a card came back at a size the zone table did
	# not say — the hand's layout tween was writing over the scale on every pass. Repairing it here would hide that.
	print("[HandHover] cards[1] scale %.4f | parent %s | zone %d | table %.4f" % [
		card.scale.x, card.get_parent().name, card.current_zone,
		float(Card.ZONE_PRESENTATION[Card.Zone.HAND]["scale"])])
	_expect(absf(card.scale.x - resting) < 0.02, "a hand card is drawn at the resting size")
	_expect(absf(card.rotation.y - hand.fan_angle_for(1)) < 0.02, "wearing its place in the fan")

	# Every OTHER card's position, so "the neighbours do not move" is measured rather than asserted.
	var before: Dictionary = {}
	for c in hand.cards:
		before[c] = c.position

	hand.set_hovered(card, true)
	await get_tree().create_timer(0.4).timeout
	print("[HandHover] hovered scale %.2f (was %.2f) = %.2fx, tilted %.2f deg" % [
		card.scale.x, resting, card.scale.x / resting, rad_to_deg(card.rotation.y)])
	_expect(card.scale.x > resting * 1.4, "a hovered card GROWS — noticeably, not just a nudge")
	_expect(absf(card.rotation.y) < 0.02, "and STRAIGHTENS UP — a leaning card cannot be read")

	# WHOLY ON SCREEN, on all four sides — that is what bringing it up is for.
	var hover_box: Dictionary = _visible(card, cam, view)
	print("[HandHover] the hovered card occupies x %.0f..%.0f, y %.0f..%.0f of a %.0f x %.0f viewport" % [
		hover_box["left"], hover_box["right"], hover_box["top"], hover_box["bottom"], view.x, view.y])
	_expect(hover_box["top"] > -1.0 and hover_box["bottom"] < view.y + 1.0,
		"it is on screen top to bottom, so the whole card can be read")
	_expect(hover_box["left"] > -1.0 and hover_box["right"] < view.x + 1.0,
		"and on screen left to right")
	_expect(card.scale.x * face.y * px_per_metre > view.y * 0.2,
		"it is big enough on screen to read the text")

	# IN FRONT. Two ways of saying the same thing, and both are needed: it must be closer to the camera than every
	# neighbour, and it must not cover their whole footprint or the pointer could never reach the next card.
	var into_screen: Vector3 = -cam.global_transform.basis.z.normalized()
	var behind: int = 0
	var highest_neighbour: float = -INF
	for c in hand.cards:
		if c == card or not is_instance_valid(c):
			continue
		# IN FRONT means CLOSER to the camera, and `into_screen` points AWAY from it — so a neighbour the hovered card
		# fails to beat is one at a POSITIVE distance along that direction. (The first version of this comparison was
		# the other way round and reported the exact opposite of the truth.)
		if (card.global_position - c.global_position).dot(into_screen) > 0.0:
			behind += 1
		highest_neighbour = maxf(highest_neighbour, c.global_position.y)
	print("[HandHover] %d of %d neighbours are in front of it" % [behind, hand.cards.size() - 1])
	_expect(behind == 0, "no neighbour can overlap it")

	# Lifted CLEAR OF ITS NEIGHBOURS, measured against them rather than against its own resting spot: the whole row
	# SINKS below the screen now, and the sink moves a card AWAY from the camera, so comparing with its own resting
	# position mostly measures the sink cancelling the lift back out.
	var rest_spot: Vector3 = hand.global_transform * before[card]
	var spot: Vector3 = card.global_position
	print("[HandHover] it moved %.3f m from its resting spot, and is %.3f m above the highest neighbour" % [
		spot.distance_to(rest_spot), spot.y - highest_neighbour])
	_expect(spot.y > highest_neighbour + 0.08, "it is LIFTED clear of every neighbour, toward the camera")

	# The step has to clear the overhang or the neighbours are unreachable with the pointer — see Hand.FAN_STEP_FRACTION.
	# Measured in PIXELS because it is a pointer target, not a look.
	var step: float = hand.card_width + hand.card_spacing
	var overhang: float = hand.card_width * ((Card.STACK_CARD_SCALE / resting) - 1.0) * 0.5
	var strip: float = step - overhang
	print("[HandHover] spacing %.3f of a %.3f card — a neighbour keeps %.0f px clear of the hover" % [
		step, hand.card_width, strip * px_per_metre])
	_expect(strip > 0.0, "a hovered card does NOT cover its neighbours' whole footprint")
	_expect(strip * px_per_metre > 40.0, "and leaves them a strip wide enough to move the pointer onto")

	# NO FLICKER: asking for the same card twice must be a no-op, or a pointer resting on one card would restart the
	# tween every frame.
	var held: Vector3 = card.position
	hand.set_hovered(card, true)
	await get_tree().process_frame
	_expect(card.position.is_equal_approx(held), "hovering the same card again changes nothing")

	# THE TEST THAT MATTERS. A real card goes on the stack and gets measured, because the point of the hover is that the
	# card is ALREADY the size it will be there — so playing it is not also a resize.
	var stack_card = game.create_card(3, "player")
	_expect(stack_card != null, "a card can be made for the stack")
	if stack_card != null:
		var stack: Node = game.get("stack")
		# WORLD scale, not local. The Stack node carries a scale of its own (2.305 in game.tscn) and card.scale is a
		# LOCAL value under it, so comparing the two cards' `scale` would compare nothing: a stack card reads 0.434
		# local and is 1.0 in the world. What the eye sees is the world scale, so that is what gets compared.
		print("[HandHover] the Stack node's own scale is %.3f" % stack.global_transform.basis.get_scale().x)
		game.add_child(stack_card)
		stack.add_card_to_tree(stack_card)
		stack.update_card_positions()
		await get_tree().create_timer(0.5).timeout
		var stack_world: float = stack_card.global_transform.basis.get_scale().x
		var hand_world: float = card.global_transform.basis.get_scale().x
		print("[HandHover] stack card is %.3f in the world   vs   hovered hand card %.3f   (local %.3f)" % [
			stack_world, hand_world, stack_card.scale.x])
		_expect(absf(hand_world - stack_world) < 0.03,
			"a hovered hand card is EXACTLY the size of a card on the stack")

	var moved: int = 0
	for c in hand.cards:
		if c == card:
			continue
		if c.position.distance_to(before[c]) > 0.001:
			moved += 1
	print("[HandHover] %d of %d neighbours moved" % [moved, hand.cards.size() - 1])
	_expect(moved == 0, "and no neighbour moves aside")

	# THE DRAG KEEPS IT. The card is picked up at hover size and stays there, so the drag is not also a resize.
	var grown: float = card.scale.x
	card.is_dragging = true
	hand.set_hovered(card, false)
	await get_tree().create_timer(0.4).timeout
	_expect(absf(card.scale.x - grown) < 0.02, "a DRAGGED card keeps the size it was picked up at")
	card.is_dragging = false

	hand.set_hovered(card, true)
	await get_tree().create_timer(0.4).timeout
	hand.set_hovered(card, false)
	await get_tree().create_timer(0.4).timeout
	print("[HandHover] after unhover, scale %.2f and tilt %.2f deg" % [
		card.scale.x, rad_to_deg(card.rotation.y)])
	_expect(absf(card.scale.x - resting) < 0.02, "and it shrinks back to the hand's size when the pointer leaves")
	_expect(absf(card.rotation.y - hand.fan_angle_for(1)) < 0.02, "leaning back into the fan as it does")

	# ---------------------------------------------------------------- 1. size, centring, and 4. the re-fan
	print("[HandHover] --- 1. every hand size fits and stays centred (and 4. re-fans) ---")
	var sweep: Array[int] = [1, 3, 7, 10, 15]
	var original: int = hand.cards.size()
	for want in sweep:
		while hand.cards.size() > want:
			var dropped: Card = hand.cards.pop_back()
			hand.remove_child(dropped)
			dropped.queue_free()
		while hand.cards.size() < want:
			var extra = game.create_card(3, "player")
			hand.add_child(extra)
			hand.cards.append(extra)
		# SMOOTHLY, NOT SNAPPED: one frame after the re-layout the cards must still be travelling toward their new
		# places, and once the tween has had its time they must be exactly where the layout says.
		var probe_card: Card = hand.cards[0]
		var was: Vector3 = probe_card.position
		hand.update_card_positions()
		var just_now: Vector3 = probe_card.position
		await get_tree().create_timer(0.35).timeout
		var settled: Vector3 = probe_card.position
		var wants: Vector3 = hand.calculate_card_position(0)
		_expect(settled.distance_to(wants) < 0.01,
			"a %d-card hand settles where the layout says" % want)
		if was.distance_to(wants) > 0.02:
			_expect(just_now.distance_to(was) < settled.distance_to(was),
				"and a %d-card hand re-fans by animating rather than snapping" % want)

		var left: float = INF
		var right: float = -INF
		var centre_sum: float = 0.0
		for c in hand.cards:
			var box: Dictionary = _visible(c, cam, view)
			left = minf(left, box["left"])
			right = maxf(right, box["right"])
			centre_sum += cam.unproject_position(c.global_position).x
		var centre: float = centre_sum / float(hand.cards.size())
		print("[HandHover] %2d cards: spans x %.0f..%.0f of %.0f; centres at %.1f (screen centre %.1f)" % [
			want, left, right, view.x, centre, view.x * 0.5])
		_expect(left >= -1.0 and right <= view.x + 1.0,
			"a %d-card hand stays on screen horizontally" % want)
		_expect(absf(centre - view.x * 0.5) < 12.0, "and a %d-card hand stays centred" % want)

	# LAST, so the checks above saw the hand as the match set it up.
	while hand.cards.size() > original:
		var extra_drop: Card = hand.cards.pop_back()
		hand.remove_child(extra_drop)
		extra_drop.queue_free()
	hand.update_card_positions()

	_finish()
