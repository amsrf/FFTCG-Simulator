extends Node3D
class_name Hand
const PRESENTATION := preload("res://scripts/core/presentation.gd")
const LOG := preload("res://scripts/core/log.gd")
## The Game this zone belongs to. Every call into the game goes through this one declared dependency rather
## than through get_parent() calls scattered around. A getter, not @onready, so it also works during _ready().
var game: Game:
	get:
		return get_node_or_null("../..")  # Player -> Game
# The list of cards in the hand

const CARD_CHARGE = 2
## Hover: the hovered card GROWS to a readable size, STRAIGHTENS UP, LIFTS toward the camera so nothing can
## overlap it, and is fitted to the bottom of the screen so its whole face can be read — see set_hovered()
## and _hover_offset(). This is the timeline for all of it.
const HOVER_SECONDS := 0.0
const HOVER_DRIFT_SECONDS := 0.30
const HOVER_DRIFT_DISTANCE := 0.04
var _hover_drift: Tween
var _hover_drift_amount := 0.0
var _pointer_hover_region := Rect2()
var _pointer_hover_active := false
## A Character drag has its own lower-band cast stance. These fields hold the
## one active drag, the X position where it latched, and whether the card has
## already been committed to mana charging.
var _character_waver_time := 0.0
var _character_drag_original_index := -1
var _character_drag_card: Card = null
var _character_drag_latched := false
var _character_drag_charging := false
var _character_drag_lock_x := 0.0
var _character_drag_restore_scale := 1.0
var _character_drag_stance := Transform3D()
var _character_drag_start := Transform3D()
var _character_drag_start_pointer_y := 0.0
## The size a hovered hand card grows to: about 225 x 315 px under the perspective camera — bigger than the resting
## hand, readable, and still clear of the field.
const HOVER_CARD_SCALE := 1.85
## How dark the artificial overlap shadow gets, and how far it fades across the covered card. These
## are art knobs, exported so they can be dialled in the Inspector without touching the shader.
@export_range(0.0, 1.0, 0.01) var overlap_shadow_strength: float = 0.62
@export_range(0.001, 0.20, 0.001) var overlap_shadow_width: float = 0.055
## The card mesh's rounded-corner radius in card-local metres (card.tres uses 0.03).
@export_range(0.0, 0.10, 0.001) var card_corner_radius_m: float = 0.03
## How far a hovered card is lifted toward the camera is NOT a constant: it has to clear the whole stacking ramp, which
## depends on how many cards are in the hand. See _hover_lift() below.
## How much clean board a hovered card keeps BELOW it, in screen pixels. Fitting to the window's edge exactly would put
## the card's bottom border and power box on the last pixel row; a short strip of board underneath keeps them readable.
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
## Centre-to-centre distance between neighbours, derived from the card's WIDTH so the overlap scales with the card.
var card_spacing = card_width * (FAN_STEP_FRACTION - 1.0);
var charging_card
var start_x;
var grabbed_card_index = 0
## The card the pointer is over, or null. Read by calculate_card_position() to make room for it.
var hovered_card: Card = null;
## While cards are tweening (hover growth, re-fan, draw landing), the shadow is recomputed
## from their CURRENT transforms each frame. Without this it was computed from the TARGET
## layout once, so it snapped to its final edge at the start of a 0.15 s hover animation.
var _shadow_track_seconds: float = 0.0
const SHADOW_TRACK_SECONDS := 0.35
signal charge_start(card:Card)
signal selected_cards_for_mana_has_changed(amount:int, element:String)
signal effect_card_selection_changed(has_selection: bool)
@onready var graveyard: Node = get_parent().get_node("Graveyard")
# Relative, not get_tree().current_scene — see damage_zone.gd. This also resolves the same
# way for Opponent/Hand, which shares this script.
@onready var stack: Stack = game.get_node("Stack") as Stack
@onready var field: Field = game.get_node("Field") as Field

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

## RETURN TO HAND, RULES half: the card is in this hand from this moment (rules, AI and effects see it at once).
## The flight is fly_returned_card(), run later by the presentation queue.
func take_returned_card(card: Card) -> void:
	if card == null or not is_instance_valid(card) or cards.has(card):
		return
	cards.append(card)
	card.index = cards.size() - 1
	card.current_zone = Card.Zone.HAND
	if card.has_signal("card_dragged") and not card.card_dragged.is_connected(Callable(self, "_on_card_dragged")):
		card.connect("card_dragged", Callable(self, "_on_card_dragged"))

## RETURN TO HAND, PRESENTATION half: grow toward the camera over the hand, then settle into the slot the card already
## owns. Starts the tween and returns it, so a mass return can fly every card at once.
func fly_returned_card(card: Card) -> Tween:
	if card == null or not is_instance_valid(card):
		return null
	var index: int = cards.find(card)
	if index < 0:
		return null
	# Make room: the rest of the fan shifts to its final layout while this card is still on its way.
	update_card_positions(index)
	var destination: Vector3 = calculate_card_position(index)

	var trans: Transform3D = card.global_transform
	if card.get_parent() != null:
		card.reparent(self, false)
	else:
		add_child(card)
	card.global_transform = trans

	var toward_camera: Vector3 = Vector3.UP
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		toward_camera = global_transform.basis.inverse() * cam.global_transform.basis.z.normalized()
	var stage: Vector3 = destination + toward_camera * return_stage_lift

	var t: Tween = create_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(card, "position", stage, return_grow_seconds)
	t.parallel().tween_property(card, "scale", Vector3.ONE * hand_scale, return_grow_seconds)
	t.parallel().tween_property(card, "rotation", Vector3.ZERO, return_grow_seconds)

	var land_fraction: float = clampf(return_land_fraction, 0.5, 1.0)
	var before: float = return_move_seconds * land_fraction
	var after: float = maxf(0.01, return_move_seconds * (1.0 - land_fraction))
	var mid: Vector3 = stage.lerp(destination, land_fraction)
	t.tween_property(card, "position", mid, before)
	t.tween_callback(_land_returned.bind(card))
	t.tween_property(card, "position", destination, after)
	return t

## Visual landing only: the card was already in `cards` (take_returned_card).
func _land_returned(card: Card) -> void:
	if card == null or not is_instance_valid(card) or not cards.has(card):
		return
	card.enter_zone(Card.Zone.HAND)
	update_card_positions()

## Draw one card: the single-card case of draw_many().
func draw(card):
	draw_many([card])

## Draw several cards AS ONE MOTION — "draw 2" reads as one draw of two, not as two draws.
##
## The cards leave the deck stacked, fan out sideways into an overlapping row while they fly, and land together; each
## then settles into its own slot. With one card this is exactly the old single draw: no offset, the path ends on its
## slot, and it gets the same flip, bump and tilt.
##
## EACH FLIGHT HAS ITS OWN Path3D/PathFollow3D. They used to share the scene's one PathFollow3D, so two draws started
## close together (the Draw Phase followed by a "draw 1" effect) fought over its progress and teleported the first card.
##
## Returns the flight tween (finished = the cards have landed), for a caller that must not move on mid-flight.
func draw_many(drawn: Array) -> Tween:
	drawn = drawn.filter(func(c): return c != null and is_instance_valid(c))
	if drawn.is_empty():
		return null
	var count: int = drawn.size()
	var first_index: int = cards.size()
	var starts: Array = []
	for card in drawn:
		add_card_to_tree(card)
		starts.append(card.position)

	# Each flight gets its own path, built like the scene's $Path3D (identity, child of the hand).
	var path := Path3D.new()
	add_child(path)
	var path_follow := PathFollow3D.new()
	path_follow.rotation_mode = PathFollow3D.ROTATION_NONE
	path_follow.loop = false
	path.add_child(path_follow)

	# The group flies to the CENTRE of its landing slots; with one card that is the slot itself.
	var landing := Vector3.ZERO
	for i in range(count):
		landing += calculate_card_position(first_index + i)
	landing /= float(count)
	var start: Vector3 = starts[0]

	# A SINGLE ARC — one cubic from the deck to the hand, so the cards move in one smooth motion.
	#
	# THE CLIMB IS IN -Z, NOT IN Y. This camera looks almost straight down, so a path that rises in world Y is
	# foreshortened to nothing and the card appears to travel flat across the board. In this rig "up the screen" is -Z.
	#
	# THE CONTROL POINT SITS ABOVE (AND RIGHT OF) THE DESTINATION, NOT ABOVE THE MIDDLE OF THE CHORD. A Bezier leaves
	# its start heading AT its control point and arrives heading AWAY from it, so the card sets off up-and-right, sweeps
	# out past the hand and hooks back down into it — the reference's tight hook. 2.6 right and 5.0 up were measured
	# off that reference (crest ~350 px beyond the hand).
	var control: Vector3 = Vector3(landing.x + 2.6, landing.y, landing.z - 5.0)
	var curve := Curve3D.new()
	curve.add_point(start)
	curve.add_point(landing)
	# Both handles at the two thirds a quadratic Bezier takes when written as a cubic — exactly one arc, no kink.
	curve.set_point_out(0, (control - start) * (2.0 / 3.0))
	curve.set_point_in(1, (control - landing) * (2.0 / 3.0))
	# SMALL, or the path is a bent polyline through the control points rather than a curve.
	curve.bake_interval = 0.05
	path.curve = curve
	path_follow.progress_ratio = 0.0
	# Put the follower on the start NOW: the cards are about to be placed relative to it this frame.
	path_follow.position = start

	# THE ROW. Neighbours sit ROW_STEP card widths apart, centred on the group — measured in CARD WIDTHS, not hand
	# slots, because the slots tighten as the hand fills and the in-flight 1.45x zoom widens the cards: at 0.9 about
	# 60% of the card underneath stays visible at the peak of the zoom. A slight lift per card keeps the later card on
	# top, as in the fan. The hand spacing takes over as they settle.
	const ROW_STEP := 0.9
	var row_offsets: Array = []
	for i in range(count):
		row_offsets.append(Vector3((i - (count - 1) / 2.0) * card_width * ROW_STEP, 0.002 * i, 0.0))

	var tween := create_tween()
	for i in range(count):
		var card: Card = drawn[i]
		card.reparent(path_follow)
		# Leave the deck as one stack (every card where the first one is), then spread while flying.
		card.position = Vector3(0.0, 0.002 * i, 0.0)
		# THE FLIP. The deck is turned over about X, but add_card_to_tree() ran enter_zone(HAND), which ASSIGNS the
		# hand's rotation (zero) — so without this the card would be face-up from the first frame. Y stays ZERO, not
		# the fan tilt: a card in the air must not wear its hand tilt (see _tilt_into_hand()).
		card.rotation = Vector3(PI, 0.0, 0.0)

	# Laid out only now: the cards in flight are parented to the path, so the layout leaves them alone and only makes
	# room for them among the cards already in hand.
	update_card_positions()

	# THE FLIGHT: 1.7 s, quickest off the deck and easing into the hand. (1.3 was too fast to follow the turn; 1.9
	# was stately. A two-stage ease read as a change of pace part-way — one EASE_OUT already has the tail.)
	tween.tween_property(path_follow, "progress_ratio", 1.0, 1.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	for i in range(count):
		var card: Card = drawn[i]
		# THE FLIP starts at once and is done well before arrival: 0.9 s of the 1.7 s flight lands the last degree at
		# ~78% of the path, and what follows is the approach into the hand.
		tween.parallel().tween_property(card, "rotation", Vector3.ZERO, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		# THE SPREAD: the cards fan apart over the first part of the climb, so they leave as one stack and travel as a row.
		if count > 1:
			tween.parallel().tween_property(card, "position", row_offsets[i], 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		# AND IT COMES TOWARDS THE VIEWER on the way, settling as it lands — Arena's beat that makes a draw read as
		# leaving the deck and arriving in the hand. A RATIO on the hand's resting size (hand_scale), its own tween so
		# it does not fight the flight tween.
		var bump: Tween = create_tween()
		bump.tween_property(card, "scale", Vector3.ONE * hand_scale * 1.45, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		bump.tween_property(card, "scale", Vector3.ONE * hand_scale, 1.2).set_trans(Tween.TRANS_SINE)

	# The cards only BECOME hand cards here — at the end of the flight.
	tween.tween_callback(_land_drawn.bind(drawn, path))
	return tween

## End of a draw flight: back into the hand, into their slots, then the fan tilt. With one card the path ended on its
## slot, so the re-layout does not move it.
func _land_drawn(drawn: Array, path: Path3D) -> void:
	for card in drawn:
		if card != null and is_instance_valid(card) and card.get_parent() != self:
			card.reparent(self)
	if drawn.size() > 1:
		update_card_positions()
	for card in drawn:
		if card != null and is_instance_valid(card) and cards.has(card):
			_tilt_into_hand(card)
	if is_instance_valid(path):
		path.queue_free()

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
	if card.has_signal("card_dragged") and not card.card_dragged.is_connected(Callable(self, "_on_card_dragged")):
		card.connect("card_dragged", Callable(self, "_on_card_dragged"))
	# Store the card's global transform before reparenting — only when it has a parent: a fresh card has no meaningful
	# global transform, and reading it outside the tree spams "!is_inside_tree()".
	if card.get_parent() != null:
		var trans: Transform3D = card.global_transform
		card.reparent(self, false)
		card.global_transform = trans
	else:
		add_child(card)
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
	_update_edge_shadows()
	_shadow_track_seconds = maxf(_shadow_track_seconds, SHADOW_TRACK_SECONDS)
	refresh_highlights()

## Recompute shadows while the hand is animating. This is a short, bounded window, not
## permanent polling: only hover growth, re-fans and draw landings need it.
func _process(delta: float) -> void:
	_update_character_waver(delta)
	if _shadow_track_seconds <= 0.0:
		return
	_shadow_track_seconds -= delta
	_update_edge_shadows()
	if _shadow_track_seconds <= 0.0:
		_shadow_track_seconds = 0.0


## ARTIFICIAL OVERLAP SHADOWS. The card underneath is darkened along the edge where the card above
## ends. Nothing is lit or cast into the world: this is a composited depth cue, so it stays exactly
## the same whatever the board light does and cannot leak onto the table.
##
## It is computed from the cards' CURRENT transforms and from each card's projected screen span,
## then recomputed for the short duration of a layout/hover tween. That makes it work for the
## player's 180-degree-rotated hand, the opponent's hand, and the grown hovered card without three
## separate left/right rules — and, crucially, the shadow travels with the card instead of snapping
## to its destination on the first frame.
func _update_edge_shadows() -> void:
	preload("res://scripts/cards/card_overlap_shadow.gd").update(self, cards,
		overlap_shadow_strength, overlap_shadow_width, card_corner_radius_m)

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
const FAN_VISIBLE_FRACTION := 0.62
## The opponent's hand shows less, which lifts it off their Backup row: at 0.62 its lower edge touched their Backups.
const MIRRORED_VISIBLE_FRACTION := 0.45
## How much lower the outermost card sits than the middle one, as a fraction of a card's HEIGHT. The drop is this times
## `r * r`, where `r` is the card's offset from the middle over half the row — so it is a `t * t` curve, symmetric by
## construction, and it can never exceed this fraction however big the hand gets. THE MIDDLE IS HIGHEST.
##
## IT HAS TO BEAT THE LEAN'S CORNER LIFT. A card leaning outward about its own centre lifts its outer corner — at
## 2 degrees and 161 px that is about 10 px — so a smaller sag is cancelled by it and the row reads as FLAT, or as
## "the edges are higher". These two are calibrated so an EIGHT-card hand drops its ends about 27 px.
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
## prompt glow of a card behind shines through the card lying in front of it — which is why this is not simply the
## smallest number that sorts correctly. Extra depth costs nothing on screen, so 20 mm keeps the order unambiguous.
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

## Pixels per metre at `world_pos`, for a displacement PERPENDICULAR to the view axis.
##
## Orthographic: constant, so `view_h / cam.size` is the whole story. Perspective: it goes as
## 1/depth, so every screen-to-world conversion has to be evaluated at the depth it is used at
## (`cam.size` is 0 in perspective). Every conversion in the hand goes through this.
func _px_per_metre_at(world_pos: Vector3) -> float:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return 1.0
	var view_h: float = get_viewport().get_visible_rect().size.y
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return view_h / maxf(cam.size, 0.001)
	var forward: Vector3 = -cam.global_transform.basis.z.normalized()
	var depth: float = maxf(forward.dot(world_pos - cam.global_position), 0.01)
	return view_h / (2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5))

## How much of the board the camera can see across, in metres, AT THIS HAND'S DEPTH. The hand's
## `fits` test is in screen terms because that is where "off the side of the screen" means anything.
func _available_width() -> float:
	var view: Vector2 = get_viewport().get_visible_rect().size
	return view.x / maxf(_px_per_metre_at(global_position), 0.001)

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
	# PROJECTION-AGNOSTIC: the conversion below asks the camera at the hand's own depth, so orthographic and
	# perspective share the same code.
	if cam == null or cards.is_empty():
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
	# Evaluated at the CARD's depth. A displacement along the camera's up axis is perpendicular to
	# the view axis, so it does not change depth — one pass is exact in both projections.
	var px_per_metre: float = _px_per_metre_at(xf.origin)
	# WHICH EDGE, AND WHICH EDGE OF THE CARD. Ours hangs off the BOTTOM: its top edge is left FAN_VISIBLE_FRACTION of a
	# card above the bottom of the screen. A MIRRORED hand hangs off the TOP instead, so its BOTTOM edge is left the same
	# fraction below the top — which is what puts the opponent's cards up against the top of the screen rather than ours.
	var want_edge: float = view_h - (bottom - top) * FAN_VISIBLE_FRACTION
	var here: float = top
	if mirror_presentation:
		want_edge = (bottom - top) * MIRRORED_VISIBLE_FRACTION
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

func calculate_card_position(i, include_hover: bool = true) -> Vector3:
	if i < 0 or i >= cards.size():
		return Vector3.ZERO
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
	# This follows what the screen shows, even though the printed numbers disagree (measured through the camera, a
	# mirrored arc put their ends 27 px HIGHER than their middle). If it ever looks wrong the other way, this is the
	# line, and the measurement that disagrees with it is in hand_hover_probe's per-card table.
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
	if include_hover and hovered_card != null and is_instance_valid(hovered_card) and i >= 0 and i < cards.size() \
			and cards[i] == hovered_card:
		spot += _hover_offset(i, spot)
		spot += global_basis.inverse() * Vector3(0.0, 0.0, _hover_drift_amount)
	return spot


## The pointer entered or left `card`: the card GROWS to the size it will be once it is on the stack, and shrinks back
## on the way out.
##
## The size is set on the CARD, not on its mesh. That is what the drag and the zone system already use, and it is the
## CARD's scale that has to be right when it lands on the stack: growing only the mesh would leave the card at hand
## size, so playing it would shrink it and then pop it back up as it landed.
## Pointer hover retains the whole enlarged footprint while the card drifts.
## Programmatic calls to set_hovered still clear immediately (payment, drag, etc.).
func pointer_hover(card: Card, entered: bool) -> void:
	var pointer := get_viewport().get_mouse_position()
	if _pointer_hover_active and _pointer_hover_region.has_point(pointer):
		return
	set_hovered(card, entered)
	if entered and hovered_card == card:
		_pointer_hover_region = _card_screen_rect(card).grow(3.0)
		_pointer_hover_active = true

func _card_screen_rect(card: Card) -> Rect2:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Rect2()
	var half := card._card_face_size() * 0.5
	var rect := Rect2(camera.unproject_position(card.hand_mesh.to_global(Vector3(-half.x, 0, -half.y))), Vector2.ZERO)
	for corner in [Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]:
		rect = rect.expand(camera.unproject_position(card.hand_mesh.to_global(corner)))
	return rect

func _resting_card_at(pointer: Vector2) -> Card:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var ray_origin := camera.project_ray_origin(pointer)
	var ray := camera.project_ray_normal(pointer)
	var nearest: Card = null
	var nearest_distance := INF
	for i in range(cards.size()):
		var card: Card = cards[i]
		if not is_instance_valid(card) or card.get_parent() != self or card.is_dragging:
			continue
		var resting := global_transform * Transform3D(
			Basis.from_euler(Vector3(0.0, fan_angle_for(i), 0.0)).scaled(Vector3.ONE * hand_scale),
			calculate_card_position(i, false))
		var face := resting * card.hand_mesh.transform
		var plane := Plane(face.basis.y.normalized(), face.origin)
		var hit = plane.intersects_ray(ray_origin, ray)
		if hit == null:
			continue
		var local: Vector3 = face.affine_inverse() * hit
		var half := card._card_face_size() * 0.5
		if absf(local.x) > half.x or absf(local.z) > half.y:
			continue
		var distance: float = ray_origin.distance_to(hit)
		if distance < nearest_distance:
			nearest = card
			nearest_distance = distance
	return nearest

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _pointer_hover_active:
		var next := _resting_card_at(event.position)
		if next != null and next != hovered_card:
			set_hovered(next, true)
			if hovered_card == next:
				_pointer_hover_region = _card_screen_rect(next).grow(3.0)
				_pointer_hover_active = true
		elif not _pointer_hover_region.has_point(event.position):
			set_hovered(hovered_card, false)

func set_hovered(card: Card, entered: bool) -> void:
	if entered and (not is_instance_valid(card) or not cards.has(card) or card.get_parent() != self):
		return
	# THE OPPONENT'S CARDS DO NOT REACT TO THE POINTER. They are face down, and they are not the local player's to touch;
	# letting them grow, lift and straighten meant that sweeping the mouse along the top of the screen played the whole
	# hover animation on cards nobody can read.
	if mirror_presentation:
		return
	# WHILE PAYING FOR MANA the hand is a row of sources, not a reading surface: cards are clicked
	# to charge, and growing one under the pointer moves the row while the player is trying to pick
	# sources. Ignore ENTER requests; a LEAVE must still be honoured so a card already hovered when
	# the payment opened can shrink back.
	if entered and GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.PAYING_COST:
		return
	# No hover lift for the cards a dragged card passes over (Card.pointer_held).
	if entered and Card.pointer_held():
		return
	var was: Card = hovered_card
	if entered:
		hovered_card = card
	elif hovered_card == card:
		hovered_card = null
	# Unchanged request: leave a pointer drifting within one card alone, or every frame restarts the tween.
	if hovered_card == was:
		return
	_pointer_hover_active = false
	if _hover_drift != null and _hover_drift.is_valid():
		_hover_drift.kill()
	_hover_drift_amount = 0.0
	if was != null and is_instance_valid(was):
		_size_card(was, false)
		_set_hover_edge(was, true)
	if hovered_card != null:
		_size_card(hovered_card, true)
		_set_hover_edge(hovered_card, false)
	update_card_positions()
	if was != null and is_instance_valid(was) and cards.has(was) and not was.is_dragging:
		was.stop_hand_layout()
		was.position = calculate_card_position(was.index)
		was.rotation = Vector3(0.0, fan_angle_for(was.index), 0.0)
	if hovered_card != null:
		_hover_drift = create_tween()
		_hover_drift.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_hover_drift.tween_method(_apply_hover_drift, 0.0, HOVER_DRIFT_DISTANCE, HOVER_DRIFT_SECONDS)

func _apply_hover_drift(amount: float) -> void:
	_hover_drift_amount = amount
	if is_instance_valid(hovered_card) and hovered_card.get_parent() == self and not hovered_card.is_dragging:
		var current_index: int = cards.find(hovered_card)
		if current_index < 0:
			_release_hover(hovered_card)
			return
		hovered_card.index = current_index
		hovered_card.position = calculate_card_position(current_index)
		if _pointer_hover_active:
			_pointer_hover_region = _pointer_hover_region.merge(_card_screen_rect(hovered_card).grow(3.0))
		_update_edge_shadows()



## THE HOVERED CARD'S THICKNESS EDGE IS HIDDEN. The dark rounded prism that gives a card its thickness
## reads as a heavy black band along the bottom border once the card is grown and lifted — the hover is
## seen closer than any other card. Hide it for the duration; the rest of the fan keeps its edge.
func _set_hover_edge(card: Card, on: bool) -> void:
	var edge := card.get_node_or_null("CardEdge") as MeshInstance3D
	if edge != null:
		edge.visible = on


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
## Clearing the whole ramp is the requirement, so the lift IS the whole ramp plus a margin. Under an
## orthographic camera the lift is free — it changes depth and nothing else. Under perspective it also
## makes the card slightly larger, which reads as "coming toward you" and is desirable for a hover.
func _hover_lift() -> float:
	return (float(cards.size()) + 2.0) * CARD_STACK_HEIGHT

func _hover_offset(i: int, base: Vector3) -> Vector3:
	# LIFT FIRST, ALWAYS, AND ALONG THE CAMERA'S OWN AXIS. Under an orthographic camera that costs not one pixel of
	# screen movement — the card changes depth and nothing else — which is what a layer change should be made of. Doing it
	# in Z would slide the card up the screen, which is a repositioning, not a layer change.
	var cam: Camera3D = get_viewport().get_camera_3d()
	var lift: Vector3 = Vector3.UP * _hover_lift()
	if cam != null:
		# WORLD camera axis -> LOCAL offset. `base` is local and the player hand is yawed 180 degrees, so adding the
		# world vector directly would tilt the lift away from the view axis and the leftmost card would stop clearing
		# its neighbours.
		lift = global_transform.basis.inverse() \
			* (cam.global_transform.basis.z.normalized() * _hover_lift())
	if cam == null:
		return lift
	var card: Card = cards[i]
	var half: Vector2 = card._card_face_size() * 0.5
	# Measured at the size it is GROWING TO and UPRIGHT, because that is what the fit is for: update_card_positions()
	# untilts the hovered card, and fitting a tilted one would leave the upright card sitting somewhere else.
	var placement: Transform3D = global_transform * Transform3D(
		Basis().scaled(Vector3.ONE * HOVER_CARD_SCALE), base + lift)
	# Unrolled rather than looped: the four corners of a quad, and this way there is no Variant in a Transform3D
	# multiply.
	var lowest: float = -INF
	lowest = maxf(lowest, cam.unproject_position(placement * Vector3(-half.x, 0.0, -half.y)).y)
	lowest = maxf(lowest, cam.unproject_position(placement * Vector3(half.x, 0.0, -half.y)).y)
	lowest = maxf(lowest, cam.unproject_position(placement * Vector3(-half.x, 0.0, half.y)).y)
	lowest = maxf(lowest, cam.unproject_position(placement * Vector3(half.x, 0.0, half.y)).y)
	var view_h: float = get_viewport().get_visible_rect().size.y
	# At the CARD's depth, after the lift. Moving along the camera's up axis is perpendicular to the
	# view axis, so the fit does not change its own scale while it solves.
	var px_per_metre: float = _px_per_metre_at(placement.origin)
	# AND IT FITS TO A LINE ABOVE THE EDGE, NOT TO THE EDGE ITSELF: on the last pixel row every corner is on screen, but
	# the bottom border and the power box are pressed against the window edge and read as cut off.
	var want_bottom: float = view_h - HOVER_BOTTOM_MARGIN
	# Screen Y grows DOWNWARD, so a positive (want_bottom - lowest) means the card sits too high and must come down.
	var world_move: Vector3 = -cam.global_transform.basis.y.normalized() * ((want_bottom - lowest) / px_per_metre)
	return lift + global_transform.basis.inverse() * world_move


## Grow or shrink one card between the hand's resting size and the readable hover size.
func _size_card(card: Card, grown: bool) -> void:
	if card == null or not is_instance_valid(card) or card.current_zone != Card.Zone.HAND:
		return
	# NOT WHILE IT IS IN THE AIR. A card being drawn is already in the HAND zone but parented to a PathFollow, and its
	# scale belongs to the draw tween — growing it here would fight that. Same guard update_card_positions() uses.
	if card.get_parent() != self:
		return
	# A card being dragged KEEPS the size it grew to: shrinking it under the pointer would only make it
	# grow again on the way there. The destination zone re-scales it on arrival.
	if not grown and card.is_dragging:
		return
	# THE HOVER SIZE, deliberately NOT Card.STACK_CARD_SCALE. That value was tuned for the orthographic
	# board, where the hand and the stack were the same size on screen. Under perspective the hand is much
	# closer to the camera, so 2.8 produced a card that covered half the board. The stack keeps its own
	# world size; the hover is optimised for reading.
	card.tween_to_scale(HOVER_CARD_SCALE if grown else hand_scale, HOVER_SECONDS)


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
	
## CHARACTER CAST STANCE. While a Character drag is below this screen-Y
## threshold it behaves like a normal hand drag. Pushing the pointer above the
## threshold latches it into the lower cast stance; coming back below the
## threshold before mana charging is engaged resumes the normal drag.
@export_range(0.55, 0.95) var character_drag_trigger_y: float = 0.80
## Screen-Y of the latched card's centre, as a fraction of viewport height.
@export_range(0.50, 0.95) var character_drag_screen_y: float = 0.74
## Screen-facing scale of the latched card.
@export_range(0.5, 3.0) var character_drag_scale: float = 1.65
## Pitch around the card's local X. Negative rotates the top edge back under
## the right-hand rule with +X to the right.
@export_range(-80.0, 0.0) var character_drag_pitch_degrees: float = -60.0
## World-Y lift for the latched card, so it leaves the mat and reads larger.
@export_range(0.0, 2.0) var character_drag_lift_y: float = 0.45

## `start_pointer_y` is where the grab happened, in screen pixels; it defaults to the real mouse. The latch measures
## how far the pointer has risen from here, so tests pass it explicitly (a headless mouse sits at the top of the screen).
func begin_character_drag(card: Card, start_pointer_y: float = -1.0) -> void:
	_character_waver_time = 0.0
	_character_drag_original_index = cards.find(card)
	_character_drag_card = card
	_character_drag_latched = false
	_character_drag_charging = false
	_character_drag_lock_x = 0.0
	_character_drag_restore_scale = card.scale.x if card != null else 1.0
	_character_drag_stance = Transform3D()
	_release_hover(card)
	card.stop_hand_layout()
	_character_drag_start = card.global_transform
	_character_drag_start.origin.y += character_drag_lift_y
	card.set_cast_pending_highlight(false)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var axes := camera.global_basis.orthonormalized()
		_character_drag_start.basis = Basis(axes.x, axes.z, -axes.y).scaled(card.global_basis.get_scale())
	_character_drag_start_pointer_y = start_pointer_y if start_pointer_y >= 0.0 else get_viewport().get_mouse_position().y
	_character_drag_start = _fit_character_drag_bottom(card, _character_drag_start, 1.10)
	card.global_transform = _character_drag_start

func character_drag_latched() -> bool:
	return _character_drag_latched

func begin_character_charge(card: Card) -> void:
	_character_drag_card = card
	_character_drag_latched = true
	_character_drag_charging = true

func end_character_drag(card: Card = null) -> void:
	if card != null and card != _character_drag_card:
		return
	if is_instance_valid(_character_drag_card):
		_character_drag_card.set_cast_pending_highlight(false)
	_character_waver_time = 0.0
	_character_drag_card = null
	_character_drag_latched = false
	_character_drag_charging = false
	_character_drag_lock_x = 0.0
	_character_drag_restore_scale = 1.0
	_character_drag_stance = Transform3D()

## Returns true while the stance owns the card's transform. False means the
## caller should run the ordinary mouse-plane drag update.
func update_character_drag(card: Card, pointer: Vector2) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	if card != _character_drag_card:
		begin_character_drag(card)
	if _character_drag_charging:
		_apply_character_waver()
		return true
	var viewport_size := get_viewport().get_visible_rect().size
	var threshold: float = viewport_size.y * character_drag_trigger_y
	# Reach full pitch at the cast boundary; allow a short motion for a grab above it.
	var finish_y: float = minf(threshold, _character_drag_start_pointer_y - viewport_size.y * 0.02)
	var progress := clampf((_character_drag_start_pointer_y - pointer.y) / maxf(1.0, _character_drag_start_pointer_y - finish_y), 0.0, 1.0)
	if not _character_drag_latched:
		_character_drag_stance = _build_character_drag_stance(pointer.x)
		_character_drag_stance.origin.y = _character_drag_start.origin.y
		# Hold the horizontal position during the pitch, then lock the completed stance.
		_character_drag_stance.origin.x = _character_drag_start.origin.x
		_character_drag_stance = _fit_character_drag_bottom(card, _character_drag_stance, 0.94)
	_character_drag_latched = progress >= 1.0
	card.set_cast_pending_highlight(_character_drag_latched and card.can_be_played())
	var amount := smoothstep(0.0, 1.0, progress)
	card.global_transform = _character_drag_start.interpolate_with(_character_drag_stance, amount)
	if _character_drag_latched:
		_apply_character_waver()
	else:
		_character_waver_time = 0.0

	return true

## Small, bounded motion layered over the ready pose; never accumulated into it.
func _update_character_waver(delta: float) -> void:
	if not _character_drag_latched or not is_instance_valid(_character_drag_card):
		return
	if _character_drag_card.get_parent() != self or _character_drag_card.current_zone != Card.Zone.HAND:
		return
	_character_waver_time += delta
	_apply_character_waver()

func _apply_character_waver() -> void:
	if not is_instance_valid(_character_drag_card):
		return
	var t := _character_waver_time
	var fade := smoothstep(0.0, 0.3, t)
	var pose := _character_drag_stance
	var tilt := Vector3(sin(t * 2.3) * 0.6, sin(t * 1.7) * 0.3, sin(t * 1.9) * 0.45) * (PI / 180.0) * fade
	pose.basis = pose.basis * Basis.from_euler(tilt)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		pose.origin += (camera.global_basis.x * sin(t * 1.6) * 0.006 + camera.global_basis.y * sin(t * 2.1) * 0.004) * fade
	_character_drag_card.global_transform = pose

## Fit the visible face to the screen bottom by moving only along world Z.
## Y stays lifted above the hand and field throughout the drag.
func _fit_character_drag_bottom(card: Card, pose: Transform3D, screen_fraction: float) -> Transform3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return pose
	var target_y := get_viewport().get_visible_rect().size.y * screen_fraction
	var half := card._card_face_size() * 0.5
	for _step in range(16):
		var bottom := -INF
		var shifted_bottom := -INF
		for corner in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(-half.x, 0, half.y), Vector3(half.x, 0, half.y)]:
			var world_point: Vector3 = pose * (card.hand_mesh.transform * corner)
			bottom = maxf(bottom, camera.unproject_position(world_point).y)
			shifted_bottom = maxf(shifted_bottom, camera.unproject_position(world_point + Vector3(0, 0, 0.01)).y)
		if absf(target_y - bottom) < 0.25:
			break
		var derivative: float = (shifted_bottom - bottom) / 0.01
		if absf(derivative) < 0.001:
			break
		pose.origin.z += clampf((target_y - bottom) / derivative, -0.5, 0.5)
	return pose

func _build_character_drag_stance(pointer_x: float) -> Transform3D:
	var camera := get_viewport().get_camera_3d()
	var viewport_size := get_viewport().get_visible_rect().size
	if camera == null:
		return Transform3D()
	# Keep the whole card on screen when the crossing happened near an edge.
	var screen := Vector2(
		clampf(pointer_x, viewport_size.x * 0.08, viewport_size.x * 0.92),
		viewport_size.y * character_drag_screen_y)
	var ray_origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	# ABOVE THE HAND, not at the mat surface — otherwise the fan (at hand height) draws over the stance card. Lifting
	# from the hand's own Y keeps the card in front of every fan card as well as larger.
	var plane_y: float = global_position.y + character_drag_lift_y
	var hit = Plane(Vector3.UP, plane_y).intersects_ray(ray_origin, ray)
	var position := ray_origin + ray * 6.0
	if hit != null:
		position = hit
	# Screen-facing basis: local X stays screen-right, local Y faces the camera,
	# local +Z is screen-down. The negative X pitch tips the card into the stance
	# shown in the reference rather than leaving it flush with the screen.
	var cam_basis := camera.global_transform.basis.orthonormalized()
	var screen_basis := Basis(cam_basis.x, cam_basis.z, -cam_basis.y)
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(character_drag_pitch_degrees))
	var basis := screen_basis * pitch
	return Transform3D(basis.scaled(Vector3.ONE * character_drag_scale), position)

func _resume_normal_character_drag(card: Card) -> void:
	card.stop_hand_layout()
	card.rotation = Vector3.ZERO
	card.scale = Vector3.ONE * _character_drag_restore_scale
	card.global_position = card._get_mouse_3d_position_on_card_plane()
	card.offset = Vector3.ZERO
	_character_drag_latched = false
	_character_drag_stance = Transform3D()

func _on_card_dragged(card: Variant) -> void:
	var new_index = find_index(card)
	if(card.index != new_index):
		move_element(cards,card.index,new_index)
		update_card_positions()
		card.index = new_index
	
func _release_hover(card: Card) -> void:
	# A card leaving the hand must stop being the hovered card. The pointer is
	# often still over it when it is dragged out, so mouse_exited never fires;
	# without this, the returned card is laid out at the hover offset (lifted and
	# grown) instead of joining the fan.
	if hovered_card == card:
		_pointer_hover_active = false
		if _hover_drift != null and _hover_drift.is_valid():
			_hover_drift.kill()
		_hover_drift_amount = 0.0
		hovered_card = null


## STAGE THE OPPONENT'S CAST AT THE MIDDLE OF THE FAN. The opponent's hand cards are all
## identical face-down backs, so moving the card being cast to the middle is invisible. It
## means the flight starts from a card the player can ALREADY SEE in the hand, instead of
## appearing at the middle only when the animation starts.
func stage_cast_card_at_middle(card: Card) -> void:
	if card == null or not cards.has(card):
		return
	var mid: int = cards.size() / 2
	cards.erase(card)
	cards.insert(mid, card)
	for i in range(cards.size()):
		cards[i].index = i
	# Kill the fan tween that may still be carrying it toward its old slot.
	if card.has_method("stop_hand_layout"):
		card.stop_hand_layout()
	# Snap the cast card onto the middle slot; it is the card being picked up.
	card.position = calculate_card_position(mid)
	card.rotation = Vector3(0.0, fan_angle_for(mid), 0.0)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		# A hair toward the camera so it reads as sitting on top of the middle card.
		card.global_position += cam.global_transform.basis.z.normalized() * 0.02

func remove_card(card):
	_release_hover(card)
	cards.erase(card)
	for i in range(cards.size()):
		cards[i].index = i
	
						
## Begins paying for a card. Returns false when it cannot legally be played now.
## A Summon leaves the hand for the parked Stack slot. A Character leaves the
## hand's card list but stays parented to the hand in its cast stance; both get
## the thin gold cast-pending aura and are blocked from mana selection.
func charge(card) -> bool:
	if card.type == Card.SUMMON:
		# Summons can be cast with a stack on it — they are the instant-speed
		# plays. They cannot be cast unless a legal target exists (when the card
		# requires one). The card leaves the hand and is parked on the stack
		# visually, but it only legally enters the stack after the cost is
		# paid and the target is confirmed.
		var criteria = card.get_cast_target_criteria()
		if not criteria.is_empty() and not field.has_viable_target(criteria, card, "Summon"):
			push_error("No viable target for %s" % card.card_name)
			return false
		# Put the opponent's cast at the middle of their face-down fan BEFORE it leaves,
		# so the animation starts from a card already visible in the hand.
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
	# A CHARACTER STAYS IN THE HAND'S CAST STANCE while its cost is paid. It is
	# removed from `cards` so the fan does not re-lay it out, and the thin gold
	# aura marks it as the play. It fades from that stance on confirm;
	# `charging_card` keeps it out of the mana selection.
	remove_card(card)
	charging_card = card
	charge_start.emit(card)
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
	return Card.PLAYER if game.turn_owner == 1 else Card.OPPONENT

func finish_summon_cast(card: Card) -> void:
	end_character_drag(card)
	# The summon left the hand when the cast began and has been parked on
	# the stack; committing it only clears the hand reference.
	if charging_card == card:
		charging_card = null

func cancel_summon_cast() -> void:
	# Return the parked summon to the hand. Nothing was paid or tapped.
	if charging_card != null:
		_on_assistant_charge_cancelled()

func has_card_matching_criteria(criteria: Dictionary) -> bool:
	for card in cards:
		if card.matches_criteria(criteria):
			return true
	return false

func _ready() -> void:
	# Highlighting is owned here: the input mode says what is selectable right
	# now, so recomputing on every mode change cannot leave a stale glow behind.
	GlobalVariables.player_mode_change.connect(_on_player_mode_change)

func _on_player_mode_change(pm: GlobalVariables.Player_Mode) -> void:
	refresh_highlights()
	# PAYMENT TURNS HOVER OFF. A card may already be grown when the payment modal opens; clear it
	# so the row is stable while the player charges sources.
	if pm == GlobalVariables.Player_Mode.PAYING_COST and hovered_card != null:
		set_hovered(hovered_card, false)

## Recompute the "selectable" glow for every card in hand from the current mode.
## One owner, derived state — no flow can leave a ring stuck on.
func refresh_highlights() -> void:
	var mode: GlobalVariables.Player_Mode = GlobalVariables.get_player_mode()
	for card in cards:
		if card.controller != Card.PLAYER:
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
	_release_hover(card)
	cards.erase(card)
	update_card_positions()

## TAKE A CARD OUT OF HAND TO PLAY IT, without charging for it (Vaan / Leon: "play ... from your hand").
## The card itself is reparented by Field.play_card(); this only stops the hand owning it, exactly like discard_card.
func remove_for_play(card: Card) -> void:
	_release_hover(card)
	cards.erase(card)
	update_card_positions()

func discard_card(card: Card) -> void:
	# Special ability (S) cost: the chosen card goes from hand to the break zone. The pile adds it immediately and
	# animates the visual flight; this method must not block on the tween.
	_release_hover(card)
	cards.erase(card)
	graveyard.call("discard", card)
	update_card_positions()
	
## Queue the payment cards' discard now if it has not been already (send_selected_cards_to_graveyard empties the
## selection, so a second call does nothing). Stack calls this before queueing a cast dissolve.
func flush_mana_discard() -> void:
	if not selected_cards_for_mana_conversion.is_empty():
		send_selected_cards_to_graveyard()

## The selected mana cards join the Break Zone at once (rules see the payment immediately); their flights are queued
## on the presentation director as one batch.
func send_selected_cards_to_graveyard() -> void:
	var spent: Array = selected_cards_for_mana_conversion.duplicate()
	cards = cards.filter(func(item): return not selected_cards_for_mana_conversion.has(item))
	selected_cards_for_mana_conversion = []
	for c in spent:
		c.reset()
	graveyard.call("discard_many", spent)
	

func add_card_to_mana_conversion(card:Card):
	# RULES: the CP cost is exact. Once fulfilled, ignore further selections. The hand-card exception (2 CP for a
	# 1-CP gap) is still allowed because the guard is checked BEFORE the card that fulfils the cost is recorded.
	var assistant = game.get("assistant") if game != null else null
	if assistant != null and assistant.payment_is_full():
		LOG.info("Mana", "cost already fulfilled; ignoring extra charge")
		return
	# A card being cast (e.g. a Summon awaiting payment) cannot be used as
	# its own mana payment.
	if card == charging_card:
		return
	# NOR CAN THE CARD ALREADY SPENT ON THIS ABILITY'S S COST. It is still IN HAND — the discard is deferred until the
	# skill commits, so that backing out can hand it back — but it is spoken for, and letting it also pay the mana would
	# spend the same card twice.
	if stack != null and stack.is_reserved_for_cost(card):
		return
	if  not selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.push_back(card)
	# Owns the marker, so an agent paying a cost gets the same feedback as a click.
	card.show_mana_crystal()
	selected_cards_for_mana_has_changed.emit(CARD_CHARGE, card.mana_element())
	
func remove_card_from_mana_conversion(card:Card):
	if selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.erase(card)
	card.clear_mana_crystal()
	selected_cards_for_mana_has_changed.emit(-CARD_CHARGE, card.mana_element())
			
func animate_card(card, target_position, target_tilt: float = 0.0):
	# POSITION AND TILT ONLY. Size belongs to the zone table and to the hover (Hand._size_card); tweening scale here
	# would override Card.ZONE_PRESENTATION and shrink a hovered card during a layout.
	#
	# The TILT is tweened here rather than assigned by the caller so that straightening up on hover, and leaning back
	# as the pointer leaves, both GLIDE. Assigning it made the straightening snap.
	# Kill the previous layout tween. If a card is picked up while the fan is
	# still moving, that tween would otherwise keep writing hand-local positions
	# after the card has been reparented to the Stack.
	if card.has_method("stop_hand_layout"):
		card.stop_hand_layout()
	if card == hovered_card:
		card.position = target_position
		card.rotation = Vector3.ZERO
		return
	var tween = create_tween()
	card.hand_tween = tween
	tween.set_parallel(true) 
	tween.tween_property(card, "position", target_position, 0.15)
	tween.tween_property(card, "rotation", Vector3(0.0, target_tilt, 0.0), 0.15)


func _on_assistant_charge_complete() -> void:
	if stack.skill_mana_deferred_until_target_confirm or stack.summon_mana_deferred_until_target_confirm:
		return
	# The Character may still be visible in its cast stance while Stack fades it
	# out; only the hand's drag bookkeeping is finished here.
	if charging_card != null:
		end_character_drag(charging_card)
	# The payment cards join the Break Zone now; their flights are queued (Stack flushes them before queueing a cast
	# dissolve, so they always play first).
	send_selected_cards_to_graveyard()
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
	# Both a Summon and a Character leave the hand while being paid for.
	# Cancelling hands the card back: a Summon is parked on the Stack, while a
	# Character is still parented to this Hand in its cast stance.
	if charging_card != null:
		end_character_drag(charging_card)
		if charging_card.get_parent() == self:
			if not cards.has(charging_card):
				cards.append(charging_card)
				charging_card.index = cards.size() - 1
				charging_card.enter_zone(Card.Zone.HAND)
		else:
			add_card(charging_card)
	if charging_card != null and cards.has(charging_card):
		cards.erase(charging_card)
		cards.insert(clampi(_character_drag_original_index, 0, cards.size()), charging_card)
	charging_card = null
	update_card_positions()

## CARD INPUT. Card forwards a click and a release to whichever zone it sits in; these are the Hand's.
## Only the player's own hand is interactive. Opponent cards use the same Hand scene but must never be
## draggable or selectable.
func on_card_grabbed(card: Card) -> void:
	if card.controller != Card.PLAYER:
		return
	match GlobalVariables.get_player_mode():
		GlobalVariables.Player_Mode.PAYING_COST:
			# The Hand owns the "selected for mana" marker (Card.show_mana_crystal).
			if selected_cards_for_mana_conversion.has(card):
				remove_card_from_mana_conversion(card)
			else:
				add_card_to_mana_conversion(card)
		GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
			# Triggered "may" choice: only criteria-matching cards can be
			# selected, and selecting one unselects the previous one.
			if card.matches_criteria(choose_card_criteria):
				toggle_effect_card_selection(card)
		_:
			card.begin_drag()
			begin_character_drag(card)

func on_card_released(card: Card) -> void:
	if card.controller != Card.PLAYER:
		return
	if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
		# Selection happens on grab; release just ends any drag state.
		card.is_dragging = false
		update_card_positions()
		card.apply_zone_scale()
		return
	# RELEASING A HAND CARD FROM THE CAST STANCE STARTS PAYMENT.
	# The stance itself is the drop confirmation: the pointer has already left
	# the hand band, so there is no extra "is the pointer over the mat" check.
	if character_drag_latched():
		# ONLY WHILE YOU HOLD PRIORITY. Against the AI this never shows, because it answers its priority at once; online
		# the other player may still be holding it, and a cast made then would happen on this machine only.
		if card.can_be_played() and field.has_priority() and charge(card):
			begin_character_charge(card)
			card.is_dragging = false
			return
		# Illegal or failed charge: put the card back in the hand.
		end_character_drag(card)
		card.is_dragging = false
		update_card_positions()
		card.apply_zone_scale()
		return
	# Below the ready boundary, release only reorders the hand.
	var new_index = find_index(card)
	end_character_drag(card)
	move_element(cards, card.index, new_index)
	card.index = new_index
	card.is_dragging = false
	update_card_positions()
	card.apply_zone_scale()
