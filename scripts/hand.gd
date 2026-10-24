extends Node3D
class_name Hand
# The list of cards in the hand

const CARD_CHARGE = 2
## Hover: the hovered card GROWS to the size it will be once it is on the stack, STRAIGHTENS UP, LIFTS toward the camera
## so nothing can overlap it, and is fitted to the bottom of the screen so its whole face can be read — see set_hovered()
## and _hover_offset(). This is the timeline for all of it.
const HOVER_SECONDS := 0.16
## How far a hovered card is lifted toward the camera is NOT a constant: it has to clear the whole stacking ramp, which
## depends on how many cards are in the hand. See _hover_lift() below.
## How much clean board a hovered card keeps BELOW it, in screen pixels. The fit used to target the viewport's bottom
## edge exactly, which is technically "fully on screen" and useless: the card's bottom border and the power box sit right
## on the last pixel row. A short strip of board underneath is what makes the bottom of the card readable.
const HOVER_BOTTOM_MARGIN := 34.0

var cards = []
@export var selected_cards_for_mana_conversion: Array[Card] = []
## "Choose a card in hand" state (triggered "may" abilities such as Auron).
var choose_card_criteria: Dictionary = {}
var selected_card_for_effect: Card = null
## The size cards are drawn at in the hand, read from Card's zone table rather than repeated here: the fan has to be
## LAID OUT for the size the cards actually are, so raising that one scale would otherwise make them silently overlap.
var hand_scale: float = float(Card.ZONE_PRESENTATION[Card.Zone.HAND]["scale"])
var card_width = GlobalVariables.get_card_width() * hand_scale;
## Centre-to-centre distance between neighbours, derived from the card's WIDTH rather than from the old absolute
## spacing: that spacing was tuned for a card less than half this size, and the overlap it gives is not the reference's.
var card_spacing = card_width * (FAN_STEP_FRACTION - 1.0);
var charging_card
var start_x;
var grabbed_card_index = 0
## The card the pointer is over, or null. Read by calculate_card_position() to make room for it.
var hovered_card: Card = null;
signal charge_start(card:Card)
signal selected_cards_for_mana_has_changed(amount:int, element:String)
signal effect_card_selection_changed(has_selection: bool)
@onready var graveyard: Node = get_parent().get_node("Graveyard")
# Relative, not get_tree().current_scene — see damage_zone.gd. This also resolves the same
# way for Opponent/Hand, which shares this script.
@onready var stack: Stack = get_node("../../Stack") as Stack
@onready var field: Field = get_node("../../Field") as Field

## RETURNING A CARD FROM THE FIELD. Two phases, tuned in the Inspector:
##   1. grow into the hand's size and rise into its plane — deliberately quick, because the card should look like it
##      has left the board rather than drift across it
##   2. slide into its slot at the end of the row; it joins the hand near the end of that slide
@export var return_grow_seconds: float = 0.2
@export var return_move_seconds: float = 0.4
## How far toward the camera the staging point sits, in metres. Without it phase 2 is a flat slide and the card
## scrapes along the other hand cards.
@export var return_stage_lift: float = 0.10
## Fraction of the slide at which the card actually joins `cards`, so the layout takes over only once it is
## essentially in place.
@export_range(0.5, 1.0, 0.01) var return_land_fraction: float = 0.85

## Start bringing a card from the field into THIS hand, and RETURN THE TWEEN so it can be joined.
##
## One chained tween, not two: a joinable animation has to be a single awaitable, or a caller doing Promise.all on
## five cards would have to track five pairs. The landing callback is a step INSIDE the chain, which is why the
## slide is split at return_land_fraction rather than scheduled by a second tween.
##
## MULTI-TARGET: the caller starts every card's tween before awaiting any of them (see Game.return_targets_to_hand),
## so they fly at the same time instead of one after another.
func begin_return_card(card: Card) -> Tween:
	if card == null or not is_instance_valid(card):
		return null

	var index: int = cards.size()
	cards.append(card)
	update_card_positions(index)
	var destination: Vector3 = calculate_card_position(index)
	cards.erase(card)

	# Keep the card's world pose across the reparent, or it teleports to the hand's origin on the first frame.
	var trans: Transform3D = card.global_transform
	if card.get_parent() != null:
		card.reparent(self, false)
	else:
		add_child(card)
	card.global_transform = trans

	# Staging point: the slot, lifted toward the camera. Phase 2 is then a visible slide into the row rather than a
	# scale change that happens to translate.
	var toward_camera: Vector3 = Vector3.UP
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		toward_camera = global_transform.basis.inverse() * cam.global_transform.basis.z.normalized()
	var stage: Vector3 = destination + toward_camera * return_stage_lift

	var t: Tween = create_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# PHASE 1 — grow to hand size and rise into the hand's plane.
	t.tween_property(card, "position", stage, return_grow_seconds)
	t.parallel().tween_property(card, "scale", Vector3.ONE * hand_scale, return_grow_seconds)
	t.parallel().tween_property(card, "rotation", Vector3.ZERO, return_grow_seconds)

	# PHASE 2 — slide in, joining the hand at return_land_fraction of the way in and carrying on to the slot.
	var land_fraction: float = clampf(return_land_fraction, 0.5, 1.0)
	var before: float = return_move_seconds * land_fraction
	var after: float = maxf(0.01, return_move_seconds * (1.0 - land_fraction))
	var mid: Vector3 = stage.lerp(destination, land_fraction)
	t.tween_property(card, "position", mid, before)
	t.tween_callback(_land_returned.bind(card))
	t.tween_property(card, "position", destination, after)
	return t

## The card is home: it becomes a real hand card, so dragging, hovering and the fan all apply to it.
func _land_returned(card: Card) -> void:
	if card == null or not is_instance_valid(card) or cards.has(card):
		return
	cards.append(card)
	card.index = cards.size() - 1
	var area = card.get_node_or_null("CardArea3D")
	if area != null and area.has_signal("card_released") and not area.card_released.is_connected(Callable(self, "_on_card_released")):
		area.connect("card_released", Callable(self, "_on_card_released"))
	if card.has_signal("card_dragged") and not card.card_dragged.is_connected(Callable(self, "_on_card_dragged")):
		card.connect("card_dragged", Callable(self, "_on_card_dragged"))
	card.enter_zone(Card.Zone.HAND)
	update_card_positions()

func draw(card):
	add_card_to_tree(card)
	update_card_positions(cards.size() - 1)
	
	var tween = create_tween()
	var path = $Path3D
	var path_follow = $Path3D/PathFollow3D
	var curve = Curve3D.new()
	var target_position = calculate_card_position(cards.size() - 1)
	
	# A SINGLE ARC — one cubic from the deck to the hand.
	#
	# This used to be a chain of FIVE control points, which made the card accelerate, kink, re-accelerate and finally
	# hook — a sequence of separate moves, which is what read as snappy.
	#
	# THE CLIMB IS IN -Z, NOT IN Y. This camera looks almost straight down, so a path that rises in world Y is
	# foreshortened to nothing and the card appears to travel flat across the board. In this rig "up the screen" is -Z.
	#
	# THE CONTROL POINT SITS ABOVE THE DESTINATION, NOT ABOVE THE MIDDLE OF THE CHORD, and that one choice is the
	# whole shape. A Bezier leaves its start heading AT its control point and arrives at its end heading AWAY from it.
	# With the control directly over the hand, the card sets off up-and-right in a long straight diagonal and comes
	# into the hand travelling straight DOWN — the tight hook the reference draws. Put the control over the midpoint
	# instead and the tangents splay outward, giving a symmetric dome that glides in from the side. Measured, both
	# crest at about the same height: it is the ARRIVAL that changes, not the climb.
	#
	# 5.0 is how tall it is; the quadratic halves it, so it crests about 2.5 above the chord. Set it by the rise you
	# want ON SCREEN, not by the number.
	var start: Vector3 = card.position
	# 5.0 of OVERSHOOT. The control sits far to the RIGHT of the destination as well as above it, so the card sweeps
	# out past the hand and hooks back left into it. Screen-right is +X in this rig.
	#
	# Measured off the reference: the arc sweeps to about x 1550 while the hand ends at x 1195 — so the crest sits
	# roughly 350 px BEYOND the hand, not just past it. In this rig that works out at ~5.0 of control offset, because
	# the crest does not follow the control one-for-one: for a quadratic the crest offset from the landing is
	# (start.x - end.x) / 4 + overshoot / 2, and the deck-to-hand run is about 4.4, so the first 2.2 is spent merely
	# cancelling the curve's natural shortfall.
	var control: Vector3 = Vector3(target_position.x + 2.6, target_position.y, target_position.z - 5.0)
	curve.add_point(start)
	curve.add_point(target_position)
	# Both handles at the two thirds a quadratic Bezier takes when written as a cubic — so the path is EXACTLY one
	# arc, with no interior kink.
	curve.set_point_out(0, (control - start) * (2.0 / 3.0))
	curve.set_point_in(1, (control - target_position) * (2.0 / 3.0))
	# SMALL, or the path is not a curve at all. `bake_interval` is the distance between baked samples, and on a curve
	# only a couple of metres long a value of 50 bakes almost nothing but the CONTROL POINTS — so the card
	# travelled a bent polyline, which is what reads as "it moves directly" instead of arcing through the middle of
	# the screen. 0.05 is roughly a thousandth of the path length.
	curve.bake_interval = 0.05
	path.curve = curve

	# Reset PathFollow3D progress
	path_follow.progress_ratio = 0

	# Configure PathFollow3D
	path_follow.rotation_mode = PathFollow3D.ROTATION_NONE

	# Reparent the card to PathFollow3D for the animation
	card.reparent(path_follow)

	# THE FLIP — and this is why the card appeared to snap face-up.
	#
	# The deck's node is turned over about X — Transform3D(1.4, 0, 0, 0, -1.4, 0, 0, 0, -1.4, ...) — so a card that
	# keeps the deck's orientation shows its BACK. But add_card_to_tree() runs enter_zone(HAND), and enter_zone ASSIGNS
	# the zone's rotation outright, which for the hand is Vector3.ZERO. That wipes the half turn before the card has
	# moved a millimetre, so it was face-up from the first frame.
	#
	# Note the Y component is ZERO, not the fan tilt: a card in the air must not wear its hand tilt. See
	# _tilt_into_hand(), which applies that once the flight is over.
	card.rotation = Vector3(PI, 0.0, 0.0)

	# THE FLIGHT: one tween, quickest off the deck and easing into the hand.
	#
	# 1.7 s — 1.5 plus the 0.2 that was asked for. It has been 1.3 → 1.9 → 1.5 → 1.7: at 1.3 the card crossed faster
	# than the eye could follow the turn, and 1.9 overcorrected into something stately.
	#
	# It was briefly TWO stages, the second covering the last fifth of the path in a third of the time, to slow the
	# arrival down. That read as unnatural — the card visibly changes pace part-way in — so it is one ease again. The
	# single EASE_OUT already spends most of its time near the end; that is the tail, and it is enough.
	tween.tween_property(path_follow, "progress_ratio", 1.0, 1.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# THE FLIP STARTS AT ONCE AND IS DONE WELL BEFORE THE CARD ARRIVES.
	#
	# Sharing the flight's duration and its default easing was wrong in two ways. The flip was on EASE_IN_OUT, which
	# holds a turn almost still for its first third — so while the flight ran ahead at full speed the card looked like
	# it was not turning at all, and the turn only became visible mid-arc. And it finished exactly as the card landed,
	# so there was no approach left.
	#
	# 0.9 s of the 1.7 s flight lands the last degree of the turn at ~78% of the PATH — the flight is QUAD EASE_OUT, so
	# 53% of the TIME is 78% of the DISTANCE. That is the draw5 frame, and what follows is the approach into the hand.
	tween.parallel().tween_property(card, "rotation", Vector3.ZERO, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

	# AND IT COMES TOWARDS THE VIEWER on the way, settling as it lands — the beat Arena uses to make a draw read as
	# the card leaving the deck and arriving in your hand rather than sliding under the table. It gets its own tween,
	# because the flight tween is already running and two tweeners on one property would fight over it.
	# 1.45x is how close it comes; 0.5 puts the peak near the top of the arc, and 1.2 settles it by the time it lands.
	# IT IS A RATIO ON THE HAND'S RESTING SIZE, and it settles BACK to that size — not to 1.0, which is not the size a
	# hand card is drawn at (see Card.ZONE_PRESENTATION and Hand.hand_scale). The 1.45 was tuned when the resting size
	# happened to be 1.0, so it is the RATIO that was tuned; keeping it a multiple preserves that.
	var bump: Tween = create_tween()
	bump.tween_property(card, "scale", Vector3.ONE * hand_scale * 1.45, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	bump.tween_property(card, "scale", Vector3.ONE * hand_scale, 1.2).set_trans(Tween.TRANS_SINE)

	# Reparent the card back to its original parent after the animation
	tween.tween_callback(card.reparent.bind(self))
	tween.tween_callback(path_follow.set.bind("progress_ratio", 0))  # Reset PathFollow3D progress
	# The card only BECOMES a hand card here — at the end of the flight.
	tween.tween_callback(_tilt_into_hand.bind(card))

## Gives an arrived card its place in the fan — the LAST step of a draw, deliberately after the flight.
##
## The fan tilt is the LAYOUT's business, and the layout must not touch a card that is still in the air. Applying it
## up front left the drawn card wearing its final tilt for the whole arc, which is what "why is the card tilting
## mid-animation" was. Tweened rather than assigned, so the card settles into the fan instead of snapping into it.
func _tilt_into_hand(card: Card) -> void:
	if card == null or not is_instance_valid(card):
		return
	var tilt: Tween = create_tween()
	tilt.tween_property(card, "rotation", Vector3(0.0, fan_angle_for(card.index), 0.0), 0.22).set_trans(Tween.TRANS_SINE)

func add_card_to_tree(card):
	cards.append(card)
	card.index = cards.size()-1
	var area = card.get_node("CardArea3D")
	if area.has_signal("card_released") and not area.card_released.is_connected(Callable(self, "_on_card_released")):
		area.connect("card_released", Callable(self, "_on_card_released"))
	if card.has_signal("card_dragged") and not card.card_dragged.is_connected(Callable(self, "_on_card_dragged")):
		card.connect("card_dragged", Callable(self, "_on_card_dragged"))
	# Store the card's global transform before reparenting
	
	# Reparent the card to the Hand
	var trans = card.global_transform
	if card.get_parent():
		card.reparent(self,false)
	else:
		add_child(card)
	card.global_transform = trans
	# A hand card is plain and flat; the fan tilt is added by the layout, so it
	# departs from this baseline (and a card arriving from the stack or from a
	# cancelled charge drops whatever it was wearing).
	card.enter_zone(Card.Zone.HAND)
	
	
func add_card(card):
	add_card_to_tree(card)
	update_card_positions()


func calculate_total_width():
	return (cards.size() * card_width) + ((cards.size() - 1) * card_spacing)

# Function to update the positions of the cards in the hand
func update_card_positions(ignore = -1):
	# THE SPACING IS RECOMPUTED HERE, and it has to be before anything reads it: spacing() depends on how many cards
	# there are and on how much room the screen has, so it changes every time the hand does. `card_spacing` is kept as
	# the derived value so the width maths below (calculate_total_width, last_card_position) stays in step.
	card_spacing = spacing() - card_width
	# Kept for last_card_position(); the fan below centres on the card index.
	start_x = -calculate_total_width() / 2 + card_width / 2

	for i in range(cards.size()):
		if(i == ignore):
			continue
		var card = cards[i]
		# A card IN FLIGHT belongs to the draw tween, not to the layout. `draw()` parents it to the PathFollow3D for
		# the duration, so anything that re-lays the hand out mid-draw — a hover is the common one, because the card
		# is drawn into the hand UNDER the pointer — would otherwise write its final position and tilt while it is
		# still travelling. That snapped the card to its fan tilt part-way through the rotation and, when the pointer
		# was already over the hand, killed the rotation outright.
		if card.get_parent() != self:
			continue
		if(card.is_dragging):
			continue
		card.index = i
		# Tilt with the arc, so the hand reads as a fan instead of a straight row — EXCEPT the hovered card, which
		# STRAIGHTENS UP. That is the card being read, and the reference's hovered card is exactly vertical. The tilt
		# is tweened inside animate_card() rather than assigned, or the straightening would snap.
		var tilt: float = 0.0 if is_hovered(i) else fan_angle_for(i)
		animate_card(card, calculate_card_position(i), tilt) # Position and tilt, relative to the Hand
	# Idempotent and cheap: keeps the selectable glow correct after draws and
	# every other layout change, not just on mode changes.
	refresh_highlights()
		
		
func last_card_position():
	return start_x + (card_width + card_spacing)*cards.size()
	
	
## Hand fan geometry.
##
## THE ROW SINKS BELOW THE SCREEN. A hand of cards is held below the edge of the table: at rest most of each card is off
## the bottom of the screen and what is left showing is the strip with the name and the cost on it. That is not
## decoration — it is what makes the hover mean something, because the hovered card is the one brought up where the
## whole of it can be read. See FAN_VISIBLE_FRACTION and _sink_offset().
##
## SPACING IS ADAPTIVE. Neighbours sit one `spacing` apart, and that spacing is the smaller of the dialled maximum and
## whatever FITS the screen — so a small hand spreads out, a big one tightens up, and the row never runs off the sides.
## See spacing(). With one card there is nothing to space and it sits centred.
##
## THE ARC AND THE LEAN ARE SEPARATE NUMBERS, deliberately. They were once one — each card tilted to be tangent to the
## arc it sits on — which tied the row's depth to how hard the cards lean: spreading the cards out, or making them
## bigger, silently leaned them harder AND bowed the row deeper at the same time.
const FAN_TILT_PER_CARD_DEGREES := 2.0
## The most any card may lean, however wide the hand gets. Past this a large hand's outer cards look like they are
## falling over rather than lying in a row.
const FAN_MAX_TILT_DEGREES := 12.0
## How much of a card is left ABOVE the bottom edge at rest; the rest hangs off the bottom. This is the number that
## decides how big the hand LOOKS, and it is measured against the card's own height, so it has to be read together with
## the card's size: 45% of a 180 px card was an 82 px strip and read as "I can barely see the cards". At 80% of a 225 px
## card the band is ~180 px, which keeps the whole cost strip and most of the art above the edge.
const FAN_VISIBLE_FRACTION := 0.80
## How much lower the outermost card sits than the middle one, as a fraction of a card's HEIGHT. The drop is this times
## `r * r`, where `r` is the card's offset from the middle over half the row — so it is a `t * t` curve, symmetric by
## construction, and it can never exceed this fraction however big the hand gets. THE MIDDLE IS HIGHEST.
##
## IT HAS TO BEAT THE LEAN'S CORNER LIFT, which is the whole reason it is 0.12 and not smaller. A card leaning outward
## about its own centre lifts its outer corner — at 2 degrees and 161 px that is about 10 px — so the old 0.06 gave a
## 14 px drop that was almost exactly cancelled by it. The row then read as FLAT, and as "the edges are higher" once the
## two landed either side of each other. These two are calibrated so an EIGHT-card hand drops its ends about 27 px.
##
## FAN_SAG_CURVE is metres of drop per metre of lateral offset SQUARED (see fan_sag_for), so the fan's depth follows the
## width of the row instead of being normalised to it. FAN_SAG_MAX caps the drop, in fractions of a card's height.
const FAN_SAG_CURVE := 0.0216
const FAN_SAG_MAX := 0.12
## The blank strip the row keeps at each side of the screen, in metres, before it starts compressing.
const FAN_SIDE_MARGIN := 0.45
## A card's height over its width — 63 x 88 mm. Only used to size things that are proportional to the CARD rather than
## to its width, the sag most of all.
const CARD_ASPECT := 1.398
## The dialled MAXIMUM spacing, as a fraction of a card's width; the rest of the card is covered by its right-hand
## neighbour. This is a ceiling, not a promise — spacing() tightens it when the hand is too wide for the screen.
##
## THIS IS AN INTERACTION NUMBER, NOT A LOOK. The hovered card is drawn on top of its neighbours at 2.4 while they rest
## at 1.6, so it is 1.5x their width and hangs (1.5 - 1) / 2 = 0.25 of a card width over each side. A neighbour is only
## reachable with the pointer while the spacing clears that — below about 0.6 the hovered card swallows them whole and
## the pointer can never get to the next card.
const FAN_STEP_FRACTION := 0.86
## Depth step per card, along the CAMERA's axis (see calculate_card_position), so it costs nothing on screen: an
## orthographic camera projected along exactly this direction, so the card does not move a pixel.
##
## It MUST stay bigger than the glow quad's offset above the card face (2 mm, see Card._build_target_border()), or the
## prompt glow of a card behind shines through the card lying in front of it — that is what the old "height stagger"
## comment was about, and it is why this is not simply the smallest number that sorts correctly.
##
## 20 mm, up from 8. It was 8 while the ramp was in world Y, where every millimetre is also a millimetre of screen
## height. Along the camera axis there is no such cost, and a stacking order is worth making unambiguous.
const CARD_STACK_HEIGHT := 0.02

## The dialled maximum spacing. EXPORTED so it can be dialled in by eye in the Inspector instead of by editing and
## re-running: select Player/Hand (or Opponent/Hand) in game.tscn, and dragging `Step Fraction` re-lays the hand out
## immediately. It is declared down here rather than with the other exports on purpose — its setter re-lays out, and the
## layout maths below has to exist first.
@export_range(0.3, 1.4, 0.01) var step_fraction: float = FAN_STEP_FRACTION:
	set(value):
		step_fraction = value
		if is_inside_tree() and is_node_ready():
			update_card_positions()

## The card's face height at the hand's resting size, for the geometry that is proportional to the CARD rather than to
## its width.
var card_height: float = card_width * CARD_ASPECT

## Centre-to-centre distance between neighbours: the dialled maximum, or whatever fits the screen with
## FAN_SIDE_MARGIN clear at each end, whichever is SMALLER. So the hand compresses smoothly as it grows and never
## overflows horizontally.
func spacing() -> float:
	var n: int = cards.size()
	if n <= 1:
		return card_width * step_fraction
	var fit: float = maxf(card_width * 0.2, _available_width() - card_width - FAN_SIDE_MARGIN * 2.0) / float(n - 1)
	return minf(card_width * step_fraction, fit)

## How much of the board the camera can see across, in metres. The hand's `fits` test is in screen terms because that is
## where "off the side of the screen" means anything.
func _available_width() -> float:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return 10.0
	var view: Vector2 = get_viewport().get_visible_rect().size
	return view.x / (view.y / maxf(cam.size, 0.001))

## The LEAN of a card in the fan, in radians — this is the card's rotation.y, and against the arc it sits on it is
## NEGATED: a card's up axis is its local -Z, so its arc position and its tilt run opposite ways. Flip only one of the
## two and the fan looks closed.
func fan_angle_for(i: int) -> float:
	var t: float = i - (cards.size() - 1) / 2.0
	var degrees: float = clampf(t * FAN_TILT_PER_CARD_DEGREES, -FAN_MAX_TILT_DEGREES, FAN_MAX_TILT_DEGREES)
	# THE LEAN IS NOT MIRRORED. Only the arc is (see calculate_card_position). This had a `turn` factor that flipped the
	# lean's sign for the opponent, on the reasoning that a mirrored arc needs a mirrored lean to stay tangent to it —
	# and the render disagrees: with the lean flipped the opponent's outer cards read as leaning INTO the row, which is
	# what "the fan looks wrong" kept being about. The two hands do not share a card orientation either, so the same
	# sign of rotation.y does not even mean the same direction on screen for them.
	return -deg_to_rad(degrees)

## How far BELOW the middle card a card sits, upward being +Z here.
##
## QUADRATIC IN THE CARD'S ACTUAL LATERAL OFFSET, capped — NOT normalised to the ends of the row. Normalising meant a
## three-card hand curved exactly as deeply as a fifteen-card one, over a quarter of the width: a two-metre row bent
## through the same 27 px as a six-metre one, which is what "the fan looks awful with three cards" was. Now the curvature
## follows the row, so a short hand is very nearly a straight line, a wide one arches, and the cap stops a big hand from
## folding itself in half.
func fan_sag_for(i: int) -> float:
	var n: int = cards.size()
	if n <= 1:
		return 0.0
	var lateral: float = (i - (n - 1) / 2.0) * spacing()
	return minf(FAN_SAG_CURVE * lateral * lateral, FAN_SAG_MAX * card_height)

## How far the whole row sits below the bottom of the screen, in the Hand's local space.
##
## Worked out from the camera on every layout rather than written down, because how much of a card ends up on screen
## depends on the card's size AND on the projection. The MIDDLE card is what is measured — the sink is applied to the
## whole row, so the arch survives it.
##
## MIRRORS THIS HAND'S PRESENTATION. One script drives both hands, and the opponent's is ours seen from the other side of
## the table: set this true on Opponent/Hand in game.tscn and everything below turns over together.
##
##   * the row hangs off the TOP edge instead of the bottom, which puts their hand up against the top of the screen,
##   * the arc curves the other way — their ends ride UP and the middle is lowest, a happy face where ours is a sad one,
##   * the lean turns over with the arc, or the outer cards would lean INTO it and the fan would look closed,
##   * the cards are dealt face DOWN, so we see backs and they see faces,
##   * and the pointer does nothing to them at all. Only the local player's cards react to being hovered.
@export var mirror_presentation: bool = false

func _sink_offset() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or cam.projection != Camera3D.PROJECTION_ORTHOGONAL or cards.is_empty():
		return Vector3.ZERO
	var half: Vector2 = cards[0]._card_face_size() * 0.5
	var xf: Transform3D = global_transform * Transform3D(Basis().scaled(Vector3.ONE * hand_scale), Vector3.ZERO)
	var top: float = INF
	var bottom: float = -INF
	for corner in [Vector3(-half.x, 0.0, -half.y), Vector3(half.x, 0.0, -half.y),
			Vector3(-half.x, 0.0, half.y), Vector3(half.x, 0.0, half.y)]:
		var y: float = cam.unproject_position(xf * corner).y
		top = minf(top, y)
		bottom = maxf(bottom, y)
	var view_h: float = get_viewport().get_visible_rect().size.y
	var px_per_metre: float = view_h / maxf(cam.size, 0.001)
	# WHICH EDGE, AND WHICH EDGE OF THE CARD. Ours hangs off the BOTTOM: its top edge is left FAN_VISIBLE_FRACTION of a
	# card above the bottom of the screen. A MIRRORED hand hangs off the TOP instead, so its BOTTOM edge is left the same
	# fraction below the top — which is what puts the opponent's cards up against the top of the screen rather than ours.
	var want_edge: float = view_h - (bottom - top) * FAN_VISIBLE_FRACTION
	var here: float = top
	if mirror_presentation:
		want_edge = (bottom - top) * FAN_VISIBLE_FRACTION
		here = bottom
	# Screen Y grows DOWNWARD, so a positive difference means the card sits too high and has to come down the screen —
	# which is the opposite direction to the camera's up axis.
	#
	# AND IT HAS TO BE BROUGHT INTO THIS NODE'S SPACE FIRST. The direction is a WORLD one and the result is added to a
	# LOCAL position — and the two hands are not rotated the same way (see game.tscn), so the raw world vector arrives
	# pointing the other way for one of them and its row moves the wrong way.
	var down: Vector3 = -cam.global_transform.basis.y.normalized()
	return (global_transform.basis.inverse() * down) * ((want_edge - here) / px_per_metre)


## The direction, in THIS hand's local space, that moves a card DOWN the screen.
##
## Any camera-derived direction has to come through the node's own basis before it is added to a local position, and
## this is that conversion in one place. It matters that it is derived rather than written as an axis: the player's Hand
## is flipped 180 degrees about Y and the opponent's is not, so the same local axis means opposite things to the two of
## them. That is what made the opponent's row bow upwards at the ends while the player's arched down.
func _screen_down() -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(0.0, 0.0, 1.0)
	return global_transform.basis.inverse() * (-cam.global_transform.basis.y.normalized())

func calculate_card_position(i) -> Vector3:
	var t: float = i - (cards.size() - 1) / 2.0
	# x is symmetric about zero, so the row is CENTRED on the Hand whatever its size is.
	var x_offset: float = t * spacing()
	# The arch: the middle highest, the ends lower. The direction comes from the CAMERA (see _screen_down), not from a
	# hard-coded axis, because the two hands are not oriented the same way: the player's Hand is flipped 180 degrees
	# about Y and the opponent's is not, so a local +Z moves one of them DOWN the screen and the other one UP. Written as
	# a fixed axis the opponent's row bowed the wrong way — its ends sat 27 px ABOVE its middle, a bowl, while the
	# player's arched correctly.
	var z_offset: float = fan_sag_for(i)
	# STACKING ORDER, and it is monotonic in `i` on purpose: a card to the RIGHT is always drawn over the one to its
	# left, so the row reads as a sequence of overlaps rather than a jumble. It also separates them far enough that a
	# glow cannot bleed through the card in front of it.
	#
	# NOT |t|, which is what this was for one revision while fixing the lopsided row. A symmetric ramp makes the CENTRE
	# the furthest card and BOTH ENDS the nearest, so the stacking flips over at the middle — the left half has the left
	# card on top and the right half has the right one, and it is the cards either side of centre that look wrong.
	#
	# AND ALONG THE CAMERA'S AXIS, not world Y. The camera is orthographic, so moving along its own axis changes a card's
	# DEPTH and nothing else — no pixels of screen movement at all. A world Y ramp is also a little bit of screen height,
	# which is what made the row look very slightly lopsided in the first place.
	var y_offset: float = 0.0
	# THE ARC DOES NOT TURN OVER. It was mirrored along with everything else, and it should not be: on screen the
	# opponent's row curves the SAME way up as ours — the ends lower than the middle — and only the LEAN is mirrored.
	#
	# That is genuinely what was reported and re-reported ("the curve is upside down"), and it disagrees with the numbers
	# this file can print: measured through the camera, the mirrored arc put their ends 27 px HIGHER than their middle.
	# Both cannot be true, the eyes looking at the screen are the authority, and the thing that has to stay consistent is
	# the screen — so the sag is no longer flipped. If it ever looks wrong the other way, this is the line, and the
	# measurement that disagrees with it is in hand_hover_probe's per-card table.
	# The camera's own back-to-front axis, in this hand's local space. Camera.basis.z points BACK toward the viewer, so
	# this is "one step nearer the camera" — depth and nothing else, because the projection is orthographic.
	var toward_cam: Vector3 = Vector3.UP
	var cam_now: Camera3D = get_viewport().get_camera_3d()
	# AND WHICH WAY IS SCREEN-RIGHT IN THIS HAND'S OWN SPACE. The ramp is driven by how far RIGHT a card is ON SCREEN,
	# not by its index. Which end of the row index 0 sits at depends on how this hand is oriented, and the two hands are
	# not oriented the same way — so an index ramp put the whole thing backwards for the player, which is what "Aerith is
	# behind Garland and Evoker behind Aerith" was. The screen is the thing that has to be consistent, not the index.
	var rightward: float = t
	if cam_now != null:
		toward_cam = global_transform.basis.inverse() * cam_now.global_transform.basis.z.normalized()
		var to_screen_right: float = global_transform.basis.x.dot(cam_now.global_transform.basis.x.normalized())
		rightward = t * (1.0 if to_screen_right >= 0.0 else -1.0)
	# THE ARC IS MIRRORED, AND THIS IS THE LINE THAT DOES IT. Their row curves the opposite way up from ours — ends
	# HIGHER than the middle, a happy face where ours is a sad one, which is what the fan looks like from where they sit.
	#
	# Measured off the render (tools/hand_outline.tscn) rather than argued about: un-mirrored, the opponent's bottom
	# outline descended from y 176 in the middle to y 208 at the ends, i.e. their ends hung 32 px LOWER than their middle.
	var mirror: float = -1.0 if mirror_presentation else 1.0
	var spot: Vector3 = Vector3(x_offset, y_offset, 0.0) \
		+ _screen_down() * (z_offset * mirror) \
		+ toward_cam * (rightward * CARD_STACK_HEIGHT) \
		+ _sink_offset()
	# FACE DOWN when mirrored: we see backs, they see faces. Done here rather than at the deal because this runs on every
	# layout, and Card.set_revealed() returns immediately when nothing has changed.
	cards[i].set_revealed(not mirror_presentation)
	if hovered_card != null and is_instance_valid(hovered_card) and i >= 0 and i < cards.size() \
			and cards[i] == hovered_card:
		spot += _hover_offset(i, spot)
	return spot


## The pointer entered or left `card`: the card GROWS to the size it will be once it is on the stack, and shrinks back
## on the way out.
##
## The size is set on the CARD, not on its mesh. That is what the drag and the zone system already use, and it is the
## CARD's scale that has to be right when it lands on the stack: growing only the mesh would leave the card at hand
## size, so playing it would shrink it and then pop it back up as it landed.
func set_hovered(card: Card, entered: bool) -> void:
	# THE OPPONENT'S CARDS DO NOT REACT TO THE POINTER. They are face down, and they are not the local player's to touch;
	# letting them grow, lift and straighten meant that sweeping the mouse along the top of the screen played the whole
	# hover animation on cards nobody can read.
	if mirror_presentation:
		return
	var was: Card = hovered_card
	if entered:
		hovered_card = card
	elif hovered_card == card:
		hovered_card = null
	# Unchanged request: leave a pointer drifting within one card alone, or every frame restarts the tween.
	if hovered_card == was:
		return
	if was != null and is_instance_valid(was):
		_size_card(was, false)
	if hovered_card != null:
		_size_card(hovered_card, true)
	# RE-LAY OUT: the hovered card's POSITION is part of the hover now — lifted toward the camera and fitted to the
	# bottom of the screen (see _hover_offset). animate_card()'s tween is what animates it out and back.
	update_card_positions()


## Where the HOVERED card has to sit so its whole face can be read: pushed toward the camera so nothing overlaps it,
## and slid until its bottom edge rests on the bottom of the screen.
##
## Returns a LOCAL offset to add to the card's fan position. It is computed from that position rather than from the
## node, because the node has not been moved yet and is mid-growth — and one pass is enough, because orthographic
## projection is affine: moving a card cannot change how big it looks, only where it lands.
## HOW FAR A HOVERED CARD IS LIFTED TOWARD THE CAMERA, in metres.
##
## DERIVED FROM THE HAND, and it has to be, because the stacking ramp ACCUMULATES: every card sits CARD_STACK_HEIGHT
## nearer than the one to its left, so the cards to a hovered card's right are up to (n - 1) steps nearer and the deepest
## of them wins the depth test. A flat 0.15 m lift loses that race from eight cards onward, which is exactly what "even
## when I hover over a card I can't see it fully" was: the cards to its right were drawn over it.
##
## Clearing the whole ramp is the requirement, so the lift IS the whole ramp plus a margin — and it is free. The lift runs
## along the camera's own axis and the camera is orthographic, so the card does not move a single pixel; only the order
## the depth buffer draws them in changes.
func _hover_lift() -> float:
	return (float(cards.size()) + 2.0) * CARD_STACK_HEIGHT

func _hover_offset(i: int, base: Vector3) -> Vector3:
	# LIFT FIRST, ALWAYS, AND ALONG THE CAMERA'S OWN AXIS. Under an orthographic camera that costs not one pixel of
	# screen movement — the card changes depth and nothing else — which is what a layer change should be made of. Doing it
	# in Z would slide the card up the screen, which is a repositioning, not a layer change.
	var cam: Camera3D = get_viewport().get_camera_3d()
	var lift: Vector3 = Vector3.UP * _hover_lift()
	if cam != null:
		lift = cam.global_transform.basis.z.normalized() * _hover_lift()
	if cam == null or cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
		# Under perspective a fit would have to be solved iteratively, because moving the card would change how big it
		# is. Better to leave it lifted than to half-do it.
		return lift
	var card: Card = cards[i]
	var half: Vector2 = card._card_face_size() * 0.5
	# Measured at the size it is GROWING TO and UPRIGHT, because that is what the fit is for: update_card_positions()
	# untilts the hovered card, and fitting a tilted one would leave the upright card sitting somewhere else.
	var placement: Transform3D = global_transform * Transform3D(
		Basis().scaled(Vector3.ONE * Card.STACK_CARD_SCALE), base + lift)
	# Unrolled rather than looped: the four corners of a quad, and this way there is no Variant in a Transform3D
	# multiply.
	var lowest: float = -INF
	lowest = maxf(lowest, cam.unproject_position(placement * Vector3(-half.x, 0.0, -half.y)).y)
	lowest = maxf(lowest, cam.unproject_position(placement * Vector3(half.x, 0.0, -half.y)).y)
	lowest = maxf(lowest, cam.unproject_position(placement * Vector3(-half.x, 0.0, half.y)).y)
	lowest = maxf(lowest, cam.unproject_position(placement * Vector3(half.x, 0.0, half.y)).y)
	var view_h: float = get_viewport().get_visible_rect().size.y
	var px_per_metre: float = view_h / maxf(cam.size, 0.001)
	# AND IT FITS TO A LINE ABOVE THE EDGE, NOT TO THE EDGE ITSELF. This used to target `view_h` exactly, which put the
	# hovered card's bottom on the LAST PIXEL ROW of the window: every corner is on screen, so the check passed, but the
	# card's bottom border and the power box just above it were pressed against the window edge and read as cut off —
	# "I can't see the power number". A card is not fully visible when the thing you want to read is on the boundary.
	var want_bottom: float = view_h - HOVER_BOTTOM_MARGIN
	# Screen Y grows DOWNWARD, so a positive (want_bottom - lowest) means the card sits too high and must come down.
	var world_move: Vector3 = -cam.global_transform.basis.y.normalized() * ((want_bottom - lowest) / px_per_metre)
	return lift + global_transform.basis.inverse() * world_move


## Grow or shrink one card between the hand's resting size and the stack's.
func _size_card(card: Card, grown: bool) -> void:
	if card == null or not is_instance_valid(card) or card.current_zone != Card.Zone.HAND:
		return
	# NOT WHILE IT IS IN THE AIR. A card being drawn is already in the HAND zone but parented to a PathFollow, and its
	# scale belongs to the draw tween — growing it here would fight that. Same guard update_card_positions() uses.
	if card.get_parent() != self:
		return
	# A card being dragged KEEPS the size it grew to: it is on its way to the stack, which draws cards at exactly
	# that size, and shrinking it under the pointer would only make it grow again on the way there.
	if not grown and card.is_dragging:
		return
	# THE STACK'S SIZE, exactly. Not a multiple of the resting size: this card is on its way to the stack, and arriving
	# there at the size it is already drawn at is the whole point of matching the two. Card.STACK_CARD_SCALE is the one
	# number behind both, and it is chosen to be readable — see the note on it in Card.
	card.tween_to_scale(Card.STACK_CARD_SCALE if grown else hand_scale, HOVER_SECONDS)


## Is the card at fan index `i` the one the pointer is over?
func is_hovered(i: int) -> bool:
	return hovered_card != null and is_instance_valid(hovered_card) \
		and i >= 0 and i < cards.size() and cards[i] == hovered_card

func find_index(card):
	var total_width = calculate_total_width()
	var card_zone_width = total_width/cards.size()
	var index : int = floor((card.position.x + (total_width / 2))/card_zone_width)
	if(index <= 0):
		return 0
	if(index >= cards.size() -1):
		return cards.size() -1 
	return index

func move_element(arr: Array, from_index: int, to_index: int) -> Array:
	if from_index < 0 or from_index >= arr.size() or to_index < 0 or to_index >= arr.size():
		return arr
	var element = arr.pop_at(from_index)
	arr.insert(to_index, element)
	return arr
	
func _on_card_dragged(card: Variant) -> void:
	var new_index = find_index(card)
	if(card.index != new_index):
		move_element(cards,card.index,new_index)
		update_card_positions()
		card.index = new_index
	
func remove_card(card):
	cards.remove_at(card.index)
	
						
## Returns false when the card cannot legally be played right now (nothing is
## charged and it stays in the hand).
func charge(card) -> bool:
	if card.type == 'Summon':
		# Summons can be cast with a stack on it — they are the instant-speed
		# plays. They cannot be cast unless a legal target exists (when the card
		# requires one). The card leaves the hand and is parked on the stack
		# visually, but it only legally enters the stack after the cost is
		# paid and the target is confirmed.
		var criteria = card.get_cast_target_criteria()
		if not criteria.is_empty() and not field.has_viable_target(criteria, card, "Summon"):
			push_error("No viable target for %s" % card.card_name)
			return false
		remove_card(card)
		charging_card = card
		charge_start.emit(card)
		return true
	# Characters are the slow plays: only the turn player may play one, and only
	# while the stack is empty. This is enforced here so it holds for the human
	# and for an agent alike.
	if not can_play_character(card):
		push_warning("[Rules] %s cannot be played now: turn player only, empty stack required" % card.card_name)
		return false
	remove_card(card)
	charge_start.emit(card)
	charging_card = card #keep reference
	return true

## A Character card is legal only for the turn player and only with an empty
## stack. (A non-turn player playing a Character needs Back Attack, which is not
## implemented.)
func can_play_character(card: Card) -> bool:
	if stack.stack_length() > 0:
		return false
	return card.controller == active_controller()

## Controller name of the side whose turn it is.
func active_controller() -> String:
	return "player" if stack.get_parent().turn_owner == 1 else "opponent"

func finish_summon_cast(card: Card) -> void:
	# The summon left the hand when the cast began and has been parked on
	# the stack; committing it only clears the hand reference.
	if charging_card == card:
		charging_card = null

func cancel_summon_cast() -> void:
	# Return the parked summon to the hand. Nothing was paid or tapped.
	if charging_card != null and charging_card.get_parent() == stack:
		add_card(charging_card)
	charging_card = null

func has_card_matching_criteria(criteria: Dictionary) -> bool:
	for card in cards:
		if card.matches_criteria(criteria):
			return true
	return false

func _ready() -> void:
	# Highlighting is owned here: the input mode says what is selectable right
	# now, so recomputing on every mode change cannot leave a stale glow behind.
	GlobalVariables.player_mode_change.connect(_on_player_mode_change)

func _on_player_mode_change(_pm: GlobalVariables.Player_Mode) -> void:
	refresh_highlights()

## Recompute the "selectable" glow for every card in hand from the current mode.
## One owner, derived state — no flow can leave a ring stuck on.
func refresh_highlights() -> void:
	var mode: GlobalVariables.Player_Mode = GlobalVariables.get_player_mode()
	for card in cards:
		if card.controller != "player":
			card.set_prompt_glow(false)
			continue
		match mode:
			GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
				# The ONLY hand glow: the game is asking the player to choose a
				# card, so mark exactly the cards that satisfy the criteria (all
				# Fire Backups for Auron's trigger, for instance).
				card.set_prompt_glow(not choose_card_criteria.is_empty() and card.matches_criteria(choose_card_criteria))
			_:
				# Everything else — a normal main phase included — stays dark. A
				# playable card is not a card the game is asking you to pick.
				card.set_prompt_glow(false)

func begin_choose_card(criteria: Dictionary) -> void:
	clear_effect_card_selection()
	choose_card_criteria = criteria
	selected_card_for_effect = null
	refresh_highlights()

func end_choose_card() -> void:
	clear_effect_card_selection()
	choose_card_criteria = {}
	selected_card_for_effect = null
	refresh_highlights()

func clear_effect_card_selection() -> void:
	if selected_card_for_effect != null:
		# Drop the "this is the one" ring with the selection — whichever colour it was wearing.
		selected_card_for_effect.set_selected_highlight(false)
		selected_card_for_effect.set_s_cost_highlight(false)
		if selected_card_for_effect.crystal_instance != null:
			selected_card_for_effect.crystal_instance.queue_free()
			selected_card_for_effect.crystal_instance = null

func toggle_effect_card_selection(card: Card) -> void:
	# Single selection: picking another card unselects the previous one.
	if selected_card_for_effect == card:
		clear_effect_card_selection()
		selected_card_for_effect = null
	else:
		clear_effect_card_selection()
		selected_card_for_effect = card
		# PINK for an S COST pick, ORANGE for every other hand choice: the S cost is a payment already made, the others
		# mean "you picked this". The STACK owns which stage is being asked for, so this asks it rather than keeping a
		# second flag in step with it — one owner, and it cannot drift.
		if stack != null and stack.s_cost_active:
			card.set_s_cost_highlight(true)
		else:
			card.set_selected_highlight(true)
		if card.crystal_scene != null:
			card.crystal_instance = card.crystal_scene.instantiate()
			card.add_child(card.crystal_instance)
			card.crystal_instance.position = Vector3(0, 0.05, -0.35)
	effect_card_selection_changed.emit(selected_card_for_effect != null)

func remove_card_for_free_play(card: Card) -> void:
	# Used by "may play for free" resolution: the chosen card leaves the hand.
	cards.erase(card)
	update_card_positions()

## TAKE A CARD OUT OF HAND TO PLAY IT, without charging for it (Vaan / Leon: "play ... from your hand").
## The card itself is reparented by Field.play_card(); this only stops the hand owning it, exactly like discard_card.
func remove_for_play(card: Card) -> void:
	cards.erase(card)
	update_card_positions()

func discard_card(card: Card) -> void:
	# Special ability (S) cost: the chosen card goes from hand to the break zone.
	cards.erase(card)
	graveyard.add_card(card)
	update_card_positions()
	
func send_selected_cards_to_graveyard():
	cards = cards.filter(func(item): return not selected_cards_for_mana_conversion.has(item))
	for c in selected_cards_for_mana_conversion:
		c.reset()
		graveyard.add_card(c)
	selected_cards_for_mana_conversion = []
	

func add_card_to_mana_conversion(card:Card):
	# A card being cast (e.g. a Summon awaiting payment) cannot be used as
	# its own mana payment.
	if card == charging_card:
		return
	# NOR CAN THE CARD ALREADY SPENT ON THIS ABILITY'S S COST. It is still IN HAND — the discard is deferred until the
	# skill commits, so that backing out can hand it back — but it is spoken for, and letting it also pay the mana would
	# spend the same card twice.
	if stack != null and card == stack.s_cost_selected_card:
		return
	if  not selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.push_back(card)
	# Owns the marker, so an agent paying a cost gets the same feedback as a click.
	card.show_mana_crystal()
	selected_cards_for_mana_has_changed.emit(2,card.element)
	
func remove_card_from_mana_conversion(card:Card):
	if selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.erase(card)
	card.clear_mana_crystal()
	selected_cards_for_mana_has_changed.emit(-2,card.element)
			
func animate_card(card, target_position, target_tilt: float = 0.0):
	# POSITION AND TILT. It used to tween the scale to 1.0 as well, which quietly made 1.0 the hand's REAL resting size:
	# whatever Card.ZONE_PRESENTATION said, every layout pass wrote 1.0 back over it. Size belongs to the zone table
	# and to the hover (Hand._size_card) — and leaving that here also meant a layout during a hover shrank the card the
	# pointer was on.
	#
	# The TILT is tweened here rather than assigned by the caller so that straightening up on hover, and leaning back
	# as the pointer leaves, both GLIDE. Assigning it made the straightening snap.
	var tween = create_tween()
	tween.set_parallel(true) 
	tween.tween_property(card, "position", target_position, 0.15)
	tween.tween_property(card, "rotation", Vector3(0.0, target_tilt, 0.0), 0.15)


func _on_assistant_charge_complete() -> void:
	if stack.skill_mana_deferred_until_target_confirm or stack.summon_mana_deferred_until_target_confirm:
		return
	send_selected_cards_to_graveyard()
	selected_cards_for_mana_conversion = []
	# A summon being cast stays referenced until targeting is resolved.
	if stack.summon_casting_card == null:
		charging_card = null
	update_card_positions()

func apply_deferred_skill_mana_payment() -> void:
	send_selected_cards_to_graveyard()
	update_card_positions()

func _on_assistant_target_cancel() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	selected_cards_for_mana_conversion.clear()


func _on_assistant_charge_cancelled() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	selected_cards_for_mana_conversion = []
	if charging_card and charging_card.get_parent() == stack:
		add_card(charging_card)
	charging_card = null
