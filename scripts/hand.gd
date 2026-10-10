extends Node3D
class_name Hand
# The list of cards in the hand

const CARD_CHARGE = 2
## Hover: the hovered card's own mesh is what lifts (mesh_instance_3d.gd), because that is presentation. The
## NEIGHBOURS making room is layout, so it happens here, in calculate_card_position().
##
## How far a neighbour slides away at full strength, and how many cards either side feel it.
const HOVER_SPREAD := 0.28
const HOVER_REACH_CARDS := 3

var cards = []
@export var selected_cards_for_mana_conversion: Array[Card] = []
## "Choose a card in hand" state (triggered "may" abilities such as Auron).
var choose_card_criteria: Dictionary = {}
var selected_card_for_effect: Card = null
var card_width = GlobalVariables.get_card_width();
var card_spacing = GlobalVariables.get_card_spacing();
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
	# 1.45 is how close it comes; 0.5 puts the peak near the top of the arc, and 1.2 settles it by the time it lands.
	var bump: Tween = create_tween()
	bump.tween_property(card, "scale", Vector3.ONE * 1.45, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	bump.tween_property(card, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_SINE)

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
		# Tilt with the arc, so the hand reads as a fan instead of a straight row.
		card.rotation = Vector3(0.0, fan_angle_for(i), 0.0)
		animate_card(card, calculate_card_position(i)) # Position relative to the Hand
	# Idempotent and cheap: keeps the selectable glow correct after draws and
	# every other layout change, not just on mode changes.
	refresh_highlights()
		
		
func last_card_position():
	return start_x + (card_width + card_spacing)*cards.size()
	
	
## Hand fan geometry: cards are spread along a shallow arc (like a hand of cards
## held in one hand) rather than in a straight row. The chord between neighbours
## stays `card_width + card_spacing`, so a bigger radius only flattens the arc.
const FAN_RADIUS := 2.4
## Height step per card. This MUST stay bigger than the glow quad's offset above
## the card face (2 mm, see Card._build_target_border()): otherwise the prompt
## glow of a card BEHIND shines through the card lying in front of it.
const CARD_STACK_HEIGHT := 0.008

## Arc angle of a card in the fan, in radians. NOTE the sign: this is the angle of
## the card's TILT (rotation.y), so left cards lean left and right cards lean
## right — a hand fan radiates OUTWARD from the pivot. calculate_card_position()
## negates it, because a card's up axis is its local -Z, so its arc position and
## its tilt run opposite ways. Flip only one of the two and the fan looks closed.
func fan_angle_for(i: int) -> float:
	var t: float = i - (cards.size() - 1) / 2.0
	return -t * (card_width + card_spacing) / FAN_RADIUS

func calculate_card_position(i):
	# Negated on purpose: see the sign note on fan_angle_for().
	var angle: float = -fan_angle_for(i)
	# x along the chord, z from the arc's sagitta: the middle card of the fan sits
	# closest to the player and the outer ones fall away.
	var x_offset: float = FAN_RADIUS * sin(angle)
	var z_offset: float = FAN_RADIUS * (1.0 - cos(angle))
	# Height stagger: separates overlapping cards, and keeps each glow behind the
	# card in front of it (see CARD_STACK_HEIGHT).
	var y_offset: float = i * CARD_STACK_HEIGHT
	# NEIGHBOURS MAKE ROOM for the hovered card: a falloff either side of it, strongest at its immediate neighbour,
	# applied along x so the fan opens up around the pointer. It belongs HERE because where the other cards sit is
	# layout, and this function owns layout — the hovered card's own lift is the mesh's job (mesh_instance_3d.gd).
	if hovered_card != null and is_instance_valid(hovered_card) and cards.has(hovered_card):
		var hovered_i: int = cards.find(hovered_card)
		var distance: int = absi(i - hovered_i)
		if distance > 0 and distance <= HOVER_REACH_CARDS:
			var strength: float = 1.0 - float(distance - 1) / float(HOVER_REACH_CARDS)
			x_offset += signf(float(i - hovered_i)) * HOVER_SPREAD * strength
	return Vector3(x_offset, y_offset, z_offset)
	
	
## The pointer entered or left `card`. Re-lays the hand out, and that tween is what animates the neighbours sliding
## away — the same path that animates a draw or a reorder, so the movement is consistent with everything else in the
## hand rather than a special case.
func set_hovered(card: Card, entered: bool) -> void:
	var was: Card = hovered_card
	if entered:
		hovered_card = card
	elif hovered_card == card:
		hovered_card = null
	# Unchanged request: do not re-lay out, or a pointer drifting within one card would restart every tween.
	if hovered_card == was:
		return
	update_card_positions()

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
		var criteria: Dictionary = card.get_cast_target_criteria()
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
		# Drop the orange "this is the one" ring with the selection.
		selected_card_for_effect.set_selected_highlight(false)
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
		# Orange = "this is the card you picked", blue = the other legal choices.
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
			
func animate_card(card, target_position):
	# Create a Tween to animate the card's movement
	var tween = create_tween()
	tween.set_parallel(true) 
	tween.tween_property(card, "position", target_position, 0.15)
	tween.tween_property(card, "scale", Vector3.ONE, 0.15)


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
