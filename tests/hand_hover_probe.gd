extends Node
## The hand's hover, and the size a card is drawn at in each place it can be.
##
## The hover is three things at once, and all three are checked here: the card GROWS to the size it will be on the
## stack, it STRAIGHTENS UP, and it PLACES ITSELF — lifted toward the camera so no neighbour can cover it, and fitted
## so its bottom edge rests on the bottom of the screen. Together those are what make the text readable, which is the
## whole point.
##
## THE SIZE TEST IS THE ONE THAT MATTERS: a card is actually put on the stack and measured, and the hovered hand card
## has to match it. Checking that two table entries agree with each other would prove nothing.

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

	# THE FAN'S GEOMETRY, straight off the reference.
	var step: float = hand.card_width + hand.card_spacing
	print("[HandHover] step %.3f of a %.3f card — %.0f%% of each card shows; outer tilt %.1f deg" % [
		step, hand.card_width, step / hand.card_width * 100.0, rad_to_deg(hand.fan_angle_for(0))])
	# The step is dialled in by eye (Hand.step_fraction) — this only checks that it reaches the layout.
	_expect(absf(step / hand.card_width - hand.step_fraction) < 0.02,
		"the fan is laid out at the step fraction the Hand is set to")
	_expect(absf(rad_to_deg(hand.fan_angle_for(0))) < 25.0,
		"and the fan leans only SLIGHTLY — under 25 degrees at the outer card of this hand")

	# AND THE ROW ITSELF IS LEVEL. The cards sit on an arc, and that bow grows with the SQUARE of the step, so a spacing
	# that looks right can still push the outer cards visibly higher than the middle ones — which is what "some cards
	# are in higher positions" turned out to be. Measured on screen, because that is where it shows.
	var top_px: float = INF
	var bottom_px: float = -INF
	var spaced: int = 0
	for i in range(hand.cards.size()):
		var c: Card = hand.cards[i]
		if c.get_parent() != hand:
			continue
		var cy: float = cam.unproject_position(hand.global_transform * c.position).y
		top_px = minf(top_px, cy)
		bottom_px = maxf(bottom_px, cy)
		spaced += 1
	print("[HandHover] the fan's %d card centres span %.1f px vertically" % [spaced, bottom_px - top_px])
	_expect(bottom_px - top_px < 12.0, "and the row reads as LEVEL — no card sits noticeably higher than another")

	var card: Card = hand.cards[1]
	# READ, DO NOT FIX UP. This check caught a real bug precisely because a card came back at a size the zone table did
	# not say — the hand's layout tween was writing over the scale on every pass. Repairing it here would hide that.
	print("[HandHover] cards[1] scale %.4f | parent %s | zone %d | table %.4f" % [
		card.scale.x, card.get_parent().name, card.current_zone,
		float(Card.ZONE_PRESENTATION[Card.Zone.HAND]["scale"])])
	_expect(absf(card.scale.x - resting) < 0.02, "and a hand card is drawn at the resting size")
	print("[HandHover] cards[1] tilts %.1f deg at rest" % rad_to_deg(card.rotation.y))
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
	_expect(card.scale.x * face.y * px_per_metre > view.y * 0.22,
		"and is tall enough on screen to read the text")
	_expect(absf(card.rotation.y) < 0.02, "it STRAIGHTENS UP — the reference's hovered card is vertical")

	# AND THE NEXT CARD MUST STILL BE REACHABLE. The hovered card is drawn ON TOP of its neighbours and is (2.4 / 1.6)
	# times their width, so it hangs half of that excess over each side. A neighbour only stays reachable while the step
	# clears that overhang — below it the hovered card swallows them whole and the pointer can never get to the next
	# card, which is what a 0.38 step did. This is measured in PIXELS because it is a pointer target, not a look.
	var overhang: float = hand.card_width * ((Card.STACK_CARD_SCALE / resting) - 1.0) * 0.5
	var strip: float = step - overhang
	print("[HandHover] a neighbour keeps a %.3f m strip = %.0f px clear of the hover   (overhang %.3f)" % [
		strip, strip * px_per_metre, overhang])
	_expect(strip > 0.0, "a hovered card does NOT cover its neighbours' whole footprint")
	_expect(strip * px_per_metre > 40.0, "and leaves them a strip wide enough to move the pointer onto")

	# THE TEST THAT MATTERS. A real card goes on the stack and gets measured, because the point of the hover is that
	# the card is ALREADY the size it will be there — so playing it is not also a resize.
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

	# AND IT PLACES ITSELF. Growing alone is not enough to read the card: it also has to come toward the camera so no
	# neighbour covers it, and sit clear of the bottom edge so the whole face is on screen.
	var rest_spot: Vector3 = hand.global_transform * before[card]
	var spot: Vector3 = card.global_position
	print("[HandHover] it moved %.3f m in total, %.3f of that toward the camera" % [
		spot.distance_to(rest_spot), spot.y - rest_spot.y])
	_expect(spot.y > rest_spot.y + 0.10, "the hovered card is LIFTED toward the camera")

	# In front of every neighbour, measured along the camera's own view direction rather than by eye.
	var into_screen: Vector3 = -cam.global_transform.basis.z.normalized()
	var behind: int = 0
	for c in hand.cards:
		if c == card or not is_instance_valid(c):
			continue
		# IN FRONT means CLOSER to the camera, and `into_screen` points AWAY from it — so a neighbour the hovered card
		# fails to beat is one at a POSITIVE distance along that direction. (The first version of this comparison was
		# the other way round and reported the exact opposite of the truth.)
		if (card.global_position - c.global_position).dot(into_screen) > 0.0:
			behind += 1
	print("[HandHover] %d of %d neighbours are in front of it" % [behind, hand.cards.size() - 1])
	_expect(behind == 0, "so no neighbour can overlap it")

	# The bottom edge on the bottom edge of the screen, measured through the same camera the player looks through.
	var half: Vector2 = face * 0.5
	var xf: Transform3D = card.global_transform
	var lowest: float = -INF
	lowest = maxf(lowest, cam.unproject_position(xf * Vector3(-half.x, 0.0, -half.y)).y)
	lowest = maxf(lowest, cam.unproject_position(xf * Vector3(half.x, 0.0, -half.y)).y)
	lowest = maxf(lowest, cam.unproject_position(xf * Vector3(-half.x, 0.0, half.y)).y)
	lowest = maxf(lowest, cam.unproject_position(xf * Vector3(half.x, 0.0, half.y)).y)
	print("[HandHover] its lowest corner is at y %.1f of a %.1f px viewport" % [lowest, view.y])
	_expect(absf(lowest - view.y) < 3.0,
		"and its bottom edge rests on the bottom of the screen, so the whole face is visible")
	_expect(lowest - face.y * card.scale.x * px_per_metre > 0.0,
		"with the card's full height above that line rather than half of it off-screen")

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

	_finish()
