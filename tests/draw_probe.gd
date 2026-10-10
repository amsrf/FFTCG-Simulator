extends Node
## Reproduces "a drawn card no longer rotates" — the draw tween animates the card's rotation, but anything that
## re-lays the hand out mid-flight hard-sets that rotation and snaps the card to its final tilt.
##
## The realistic trigger is the pointer resting over the hand: the card is drawn INTO the hand under the cursor, so
## a hover lands in the middle of the draw. This probe reproduces it deterministically by calling `set_hovered()`
## part-way through, which is exactly what `mesh_instance_3d.gd` does on `mouse_entered`.
##
## Run: godot --headless res://tests/draw_probe.tscn --quit-after 900

const GAME_SCENE := preload("res://game.tscn")
## Where in the flight to trigger the re-layout: about a fifth of the way through the flip, late enough to be
## unambiguous and early enough that a snap and a turn are far apart.
const INTERFERE_AT := 2
const SAMPLE_STEP := 0.09
## Enough samples to WATCH THE WHOLE DRAW: the flight runs 1.9 s and is followed by the settle into the fan, so
## anything shorter stops sampling while the card is still moving and cannot tell "finished" from "still going".
const SAMPLES := 28

var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var hand = game.hand
	var deck = game.get_node("Player/Deck")
	if hand == null or deck == null or deck.deck_cards.is_empty():
		print("[DrawProbe] no hand or no deck to draw from")
		get_tree().quit(1)
		return

	# Drawn through the REAL phase machine rather than by calling draw() directly: the draw is followed immediately by
	# next_phase(), which changes the input mode and runs the next phase's entry code, and that is the one thing a
	# direct call does not reproduce. The hand is left POPULATED, because that is the normal case — emptying it first
	# puts the new card at fan index 0 of a one-card hand, where the fan tilt is genuinely zero and there is nothing
	# to rotate.
	game.turn_owner = 1
	game._enter_phase(GlobalVariables.Phase.DRAW_PHASE)
	await get_tree().process_frame
	if hand.cards.is_empty():
		print("[DrawProbe] the draw phase drew nothing")
		get_tree().quit(1)
		return
	var card = hand.cards[hand.cards.size() - 1]
	print("[DrawProbe] drew %s as fan index %d of %d, parented to %s" % [
		card.card_name, card.index, hand.cards.size(), card.get_parent().name])
	print("[DrawProbe] sampling every %.2f s: LOCAL rot, GLOBAL rot" % SAMPLE_STEP)

	# The tilt the draw tween is heading for, in degrees.
	var target: float = rad_to_deg(hand.fan_angle_for(card.index))
	print("[DrawProbe] target tilt %.1f deg" % target)

	var samples: Array = []
	var globals: Array = []
	var meshes: Array = []
	var progresses: Array = []
	var points: Array = []
	var screens: Array = []
	var scales: Array = []
	var mesh: Node3D = card.get_node("HandMesh")
	# While it flies, the card is parented to the draw path — this is how far along that path it is.
	var path_follow: Node = card.get_parent()
	var cam: Camera3D = get_viewport().get_camera_3d()
	for i in range(SAMPLES):
		await get_tree().create_timer(SAMPLE_STEP).timeout
		if i == INTERFERE_AT:
			# The card is drawn INTO the hand UNDER the pointer, so what actually happens is a hover on the card that
			# is flying — and the hover writes the MESH's rotation to cancel the card's, which would make the rotation
			# invisible even though the card node is turning.
			print("[DrawProbe] -- hovering the card mid-flight, as the pointer would --")
			hand.set_hovered(card, true)
			mesh._on_card_area_3d_mouse_entered()
		# THE FLIP LIVES IN rotation.x: the deck's node is turned over about X, so 180 deg is FACE-DOWN and 0 is
		# FACE-UP. rotation.y is only the fan tilt, and it is set once at the start rather than animated.
		globals.append(rad_to_deg(card.rotation.x))
		samples.append(rad_to_deg(card.rotation.y))
		points.append(card.global_position)
		meshes.append(rad_to_deg(mesh.global_rotation.y))
		progresses.append(float(path_follow.get("progress_ratio")))
		# What the PLAYER sees: where the card lands on screen, and how big it is.
		screens.append(cam.unproject_position(card.global_position) if cam != null else Vector2.ZERO)
		scales.append(card.scale.x)

	var report: String = ""
	for i in range(samples.size()):
		report += "%s%.1f" % ["" if i == 0 else " ", samples[i]]
	print("[DrawProbe] card FAN TILT (rotation.y): %s" % report)
	report = ""
	for i in range(globals.size()):
		report += "%s%.1f" % ["" if i == 0 else " ", globals[i]]
	print("[DrawProbe] card FLIP (rotation.x): %s" % report)

	# THE FLIP CHECK. The card comes out of the deck FACE-DOWN, so rotation.x must START near 180 deg (back to the
	# player) and END near 0 (face up). It used to snap straight to face-up on the first frame, because
	# add_card_to_tree() runs enter_zone(HAND), which ASSIGNS the hand's rotation outright — that is the reported bug.
	var flip_start: float = globals[0]
	var flip_end: float = globals[globals.size() - 1]
	print("[DrawProbe] the card flips %.0f deg, ending %.0f deg from face-up" % [
		absf(flip_start - flip_end), absf(flip_end)])
	_expect(absf(flip_start) > 120.0, "the card starts FACE-DOWN (rotation.x %.0f deg)" % flip_start)
	_expect(absf(flip_end) < 5.0, "and finishes FACE-UP (rotation.x %.0f deg)" % flip_end)
	# Gradual, not a snap. This is the check that catches the bug directly: a snap puts the very first sample at 0.
	var flip_mid: float = globals[3]
	print("[DrawProbe] %.2f s in, the card is %.0f deg through its turn" % [3.0 * SAMPLE_STEP, flip_mid])
	_expect(flip_mid > 5.0 and flip_mid < 175.0,
		"and turns over gradually rather than snapping face-up")

	# IT MUST START AT ONCE. The default EASE_IN_OUT held the card almost still for the first third of the turn, so
	# while the flight accelerated away the card appeared not to be turning at all — the "the rotation only starts
	# mid-arc" report. One sample in — 0.09 s, barely after launch — it should be clearly under way.
	var flip_early: float = globals[1]
	print("[DrawProbe] %.2f s in, barely launched, the card is already %.0f deg through its turn" % [
		SAMPLE_STEP, flip_early])
	_expect(flip_early < 172.0, "the flip starts IMMEDIATELY, not mid-arc")

	# AND IT IS DONE WELL BEFORE THE CARD ARRIVES — the draw5 frame — leaving the last stretch as an approach.
	var flip_done_at: int = -1
	for i in range(globals.size()):
		if flip_done_at < 0 and absf(globals[i]) < 2.0:
			flip_done_at = i
	if flip_done_at >= 0:
		print("[DrawProbe] the flip finishes at %.2f s, %.0f%% of the way along the path" % [
			float(flip_done_at) * SAMPLE_STEP, progresses[flip_done_at] * 100.0])
		_expect(progresses[flip_done_at] > 0.55 and progresses[flip_done_at] < 0.95,
			"and it finishes on the way in, leaving the rest as a slower approach")
	report = ""
	for i in range(meshes.size()):
		report += "%s%.1f" % ["" if i == 0 else " ", meshes[i]]
	print("[DrawProbe] GLOBAL MESH rotation (what the eye sees): %s" % report)

	# IS IT AN ARC, OR A STRAIGHT LINE? Two measurements, because the 3D one is NOT what the player sees:
	#   * the 3D bow catches a path that collapsed into a polyline, which is what `bake_interval = 50` did;
	#   * the SCREEN bow is the real test. This camera looks almost straight down, so a climb in world Y is
	#     foreshortened away — the flight can bow two metres in 3D and still cross the board flat to the eye. The
	#     reference draws a tall hump, so the path has to rise well above the straight line ON SCREEN.
	var chord: Vector3 = points[points.size() - 1] - points[0]
	var bow: float = 0.0
	if chord.length() > 0.001:
		for p in points:
			var along: float = clampf((p - points[0]).dot(chord) / chord.length_squared(), 0.0, 1.0)
			bow = maxf(bow, p.distance_to(points[0] + chord * along))
	print("[DrawProbe] the path bows %.3f m off the straight line to the hand (chord %.3f m)" % [
		bow, chord.length()])
	_expect(bow > 0.15, "the card travels an ARC, not a straight line to the hand")

	# THE SHAPE IS A HOOK, NOT A DOME. The reference climbs diagonally to a crest roughly ABOVE the hand and then
	# drops almost straight into it — so the crest should sit close to the landing horizontally, and the closing leg
	# should be steeper than it is wide. A symmetric dome crests at mid-journey and glides in from the side, which is
	# what this replaces.
	var top_index: int = 0
	for i in range(screens.size()):
		if screens[i].y < screens[top_index].y:
			top_index = i
	var journey_x: float = absf(screens[screens.size() - 1].x - screens[0].x)
	# SIGNED, because the direction is the whole point: positive means the crest is to the RIGHT of the landing, i.e.
	# the arc bows out PAST the hand and hooks back left into it. That outward overshoot is what the reference has.
	var crest_offset: float = screens[top_index].x - screens[screens.size() - 1].x
	print("[DrawProbe] the crest sits %.0f px %s the landing, out of a %.0f px journey" % [
		absf(crest_offset), "RIGHT of" if crest_offset > 0.0 else "LEFT of", journey_x])
	# THE OVERSHOOT, measured the way the reference is: its RIGHTMOST point against where the card lands. The RED arc
	# turns back at x 1385 while the card lands at x 1255 — +130 px, about 14% of the 935 px deck-to-hand run. (The
	# PURPLE one reaches 1550, or 32%, and read as too much.) So this is a real but modest bow: clearly past the hand,
	# and nothing like sweeping the board.
	var right_index: int = 0
	for i in range(screens.size()):
		if screens[i].x > screens[right_index].x:
			right_index = i
	var reach: float = screens[right_index].x - screens[screens.size() - 1].x
	print("[DrawProbe] the arc reaches %.0f px %s the landing — %.0f%% of the journey" % [
		absf(reach), "RIGHT of" if reach > 0.0 else "LEFT of", absf(reach) / maxf(journey_x, 1.0) * 100.0])
	_expect(reach > 0.0, "it bows out PAST the hand to the right before turning back")
	_expect(reach < journey_x * 0.35,
		"but only modestly — the reference's own bow is 14% of the run")

	# The return comes back down-and-left into the hand.
	var tail_from: Vector2 = screens[mini(top_index + 1, screens.size() - 2)]
	var tail_to: Vector2 = screens[screens.size() - 1]
	print("[DrawProbe] the closing leg travels %.0f px down and %.0f px across" % [
		absf(tail_to.y - tail_from.y), absf(tail_to.x - tail_from.x)])
	# MEASURED FROM THE ARC'S RIGHTMOST POINT — where it turns back — rather than from the highest sample. The crest
	# and the turn-back are only a sample or two apart, and which one the sampler tops out on shifts with the frame
	# timing, so the horizontal expectation here flickered between pass and fail run to run. The turn-back point is
	# stable, and it is the right thing to measure a "return" from anyway.
	var back: Vector2 = screens[right_index]
	_expect(absf(tail_to.y - back.y) > 150.0, "and it comes back DOWN into the hand")
	_expect(absf(tail_to.x - back.x) > 100.0, "and a long way LEFT from where it turned back")

	var a: Vector2 = screens[0]
	var b: Vector2 = screens[screens.size() - 1]
	var flat: Vector2 = b - a
	var rise: float = 0.0
	if flat.length() > 1.0:
		for s in screens:
			var f: float = clampf((s - a).dot(flat) / flat.length_squared(), 0.0, 1.0)
			# Screen Y grows DOWNWARD, so "above the line" is a SMALLER y.
			rise = maxf(rise, (a + flat * f).y - s.y)
	print("[DrawProbe] on screen it rises %.0f px above the straight line, over a %.0f px journey" % [
		rise, flat.length()])
	_expect(rise > 60.0, "and it humps UP on screen, which is what the eye actually reads")

	# AND IT COMES TOWARDS THE VIEWER — the Arena beat. The card must grow noticeably at the top of the flight and
	# settle back to the hand's RESTING size, which is NOT 1.0 (see Card.ZONE_PRESENTATION) — every layout pass used to
	# write 1.0 back over it, so "settles at 1.0" was the bug rather than the expectation.
	# Both are measured AGAINST that resting size, because the growth was tuned when the resting size happened to be
	# 1.0 and what was tuned was the RATIO.
	var rest: float = float(Card.ZONE_PRESENTATION[Card.Zone.HAND]["scale"])
	var peak_scale: float = 0.0
	for sc in scales:
		peak_scale = maxf(peak_scale, sc)
	print("[DrawProbe] the card peaks at %.2fx and settles at %.2fx (the hand rests at %.2fx)" % [
		peak_scale / rest, scales[scales.size() - 1] / rest, rest])
	_expect(peak_scale > rest * 1.2, "the card comes TOWARDS the viewer mid-flight")
	_expect(absf(scales[scales.size() - 1] - rest) < 0.05, "and settles to the hand's resting size on arrival")

	# AND IT MUST FLY FLAT — no fan tilt until it has arrived. The tilt belongs to the hand's LAYOUT, and the layout
	# must not touch a card that is still in the air: applying it up front left the drawn card leaning through the
	# whole arc, which is the "why is the card tilting mid-animation" report. It is applied at the end, by
	# _tilt_into_hand().
	var tilt_mid: float = absf(samples[4])
	print("[DrawProbe] %.2f s in — in the air — the card's fan tilt is %.1f deg" % [
		4.0 * SAMPLE_STEP, tilt_mid])
	_expect(tilt_mid < 2.0, "the card flies FLAT, carrying no fan tilt")
	_expect(absf(samples[samples.size() - 1] - target) < 5.0,
		"and only takes its tilt once it has landed (%.1f)" % samples[samples.size() - 1])

	_expect(absf(samples[samples.size() - 1] - target) < 2.0, "landing on its fan tilt")

	# The re-layout must not have snapped the FLIP either: a hover mid-flight writes the layout's rotation, and the
	# turn has to survive it.
	var flip_there: float = globals[INTERFERE_AT]
	print("[DrawProbe] at the moment of the re-layout the card is %.0f deg through its turn" % flip_there)
	_expect(flip_there > 5.0 and flip_there < 175.0,
		"and a re-layout mid-flight does not snap the card face-up")

	# And it must arrive in the end, or the guard would have frozen it.
	await get_tree().create_timer(1.6).timeout
	var settled: float = rad_to_deg(card.rotation.y)
	_expect(absf(settled - target) < 1.0,
		"and it still settles on its fan tilt (%.1f vs %.1f)" % [settled, target])

	print("[DrawProbe] %d checks | failures: %d" % [_checks, _failures])
	print("[DrawProbe] RESULT: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[DrawProbe] ok   %s" % what)
	else:
		_failures += 1
		print("[DrawProbe] FAIL %s" % what)
