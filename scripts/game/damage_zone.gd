extends Node3D
class_name DamageZone
## The Game this zone belongs to. Every call into the game goes through this one declared dependency rather
## than through get_parent() calls scattered around. A getter, not @onready, so it also works during _ready().
var game: Game:
	get:
		return get_node_or_null("../..")  # Player -> Game
# The list of cards in the hand

const CARD_CHARGE = 2
## How long a damage card flies from the deck to its slot. The EX BURST reveal starts as it lands.
const FLIGHT_SECONDS := 1.3
## How high (metres, zone-local = world Y) the damage card's arc pulls up off the deck and above its slot.
const FLIGHT_LIFT := 0.6

var cards = []
var deck: Node = null
var card_width = GlobalVariables.get_card_width();
var card_spacing = -0.3
var start_x;
var grabbed_card_index = 0;
# Relative on purpose. `get_tree().current_scene` is only set to the game when the game IS
# the top-level scene, so it silently yields null for anything that instantiates it
# elsewhere (the headless probe, a future self-play or preview). Walking the tree works
# wherever the scene is mounted.
@onready var field: Field = game.get_node("Field")
@onready var assistant: Assistant = game.get_node("Assistant")

func set_deck(deck_node: Node) -> void:
	deck = deck_node

func draw(card):
	# THE CARD IS DAMAGE FROM THE MOMENT IT STARTS FLYING. enter_zone() is what normalises its presentation and sets
	# `current_zone`; only the instant path (add_card) did it, so every card that arrived through the animated draw —
	# which is every damage card in a real game — kept the DECK zone and its deck rotation/scale for good.
	# Where (and how big) the card really is in the deck, taken BEFORE enter_zone(): that assigns the damage scale while
	# the card is still inside the 1.4-scaled Deck node, so the flight started 40% too big.
	var start_xf: Transform3D = card.global_transform if card.is_inside_tree() else Transform3D()
	var was_in_tree: bool = card.is_inside_tree()
	card.enter_zone(Card.Zone.DAMAGE)
	add_card_to_tree(card)
	if was_in_tree:
		card.global_transform = start_xf
	update_card_positions(cards.size() - 1)

	# EACH FLIGHT OWNS ITS PATH. There used to be ONE shared $Path3D: two damage in the same frame (take_damage(2))
	# rewrote the curve the first card was still riding, so every card of the hit landed on the LAST slot.
	var tween = create_tween()
	var path := Path3D.new()
	add_child(path)
	var path_follow := PathFollow3D.new()
	path_follow.loop = false
	path.add_child(path_follow)
	var curve = Curve3D.new()
	var target_position = calculate_card_position(cards.size() - 1)
	var plane: float = target_position.y

	# ONE ARC FROM THE DECK TO THE SLOT: straight up off the deck, across ABOVE the board, straight down onto the slot.
	# The old five waypoints (out to 1.2 m sideways) were laid out for the zone's old place beside the deck; with the
	# zone standing above the deck they swung the card out wide and brought it in from the side.
	var start: Vector3 = card.position
	var up := Vector3.UP * maxf(FLIGHT_LIFT, plane - start.y + FLIGHT_LIFT)
	curve.add_point(start, Vector3.ZERO, up + (target_position - start) * 0.15)
	curve.add_point(Vector3(target_position), up, Vector3.ZERO)
	curve.bake_interval = 0.02
	path.curve = curve

	# Reset PathFollow3D progress
	path_follow.progress_ratio = 0

	# Configure PathFollow3D
	path_follow.rotation_mode = PathFollow3D.ROTATION_NONE

	# Reparent the card to PathFollow3D for the animation
	card.reparent(path_follow)

	# Animate the card along the path
	tween.tween_property(path_follow, "progress_ratio", 1.0, FLIGHT_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# The zone's own resting size, from the zone table (this was a hard-coded 1.2, so every new damage card stayed bigger
	# than the ones already laid out).
	var rest: float = float(Card.ZONE_PRESENTATION[Card.Zone.DAMAGE]["scale"])
	tween.parallel().tween_property(card, "scale", Vector3.ONE * rest, FLIGHT_SECONDS)
	# THE TURN: a PITCH (the flip, about the card's own width axis) and a ROTATION in the board plane (about the zone's
	# up axis, portrait in the deck to landscape here), together, and nothing else. Tweening rotation_degrees from the
	# deck's Euler angles to zero dragged it through all three axes at once, which read as a wobble/yaw.
	var start_basis: Basis = card.basis.orthonormalized()
	var face_up: Basis = start_basis * Basis(Vector3.RIGHT, PI)   # undo the face-down flip: what is left is the turn
	var turn: float = atan2(-face_up.x.z, face_up.x.x)
	var pitch: float = PI
	if start_basis.y.y > 0.0:
		# Already face up (a revealed card): only the turn.
		pitch = 0.0
		turn = atan2(-start_basis.x.z, start_basis.x.x)
	tween.parallel().tween_method(func(t: float) -> void:
		if is_instance_valid(card):
			card.quaternion = Quaternion(Basis(Vector3.UP, turn * (1.0 - t)) * Basis(Vector3.RIGHT, pitch * (1.0 - t))),
		0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Reparent the card back to its original parent after the animation
	tween.tween_callback(_land.bind(card, path))

## A flight is over: the card joins the zone's frame, its path goes, and the whole row is laid out again (the row
## re-centres as it grows, so cards that landed earlier in the same hit move to their final slots too).
func _land(card: Card, path: Node) -> void:
	if is_instance_valid(card) and card.get_parent() != self:
		card.reparent(self)
	if is_instance_valid(path):
		path.queue_free()
	update_card_positions()

func add_card_to_tree(card):
	cards.append(card)
	card.index = cards.size()-1
	var trans = card.global_transform
	if card.get_parent():
		card.reparent(self,false)
	else:
		add_child(card)
	card.global_transform = trans
	
	
func add_card(card):
	# Damage-zone cards are laid flat and must not show the field readout.
	card.enter_zone(Card.Zone.DAMAGE)
	add_card_to_tree(card)
	update_card_positions()


func calculate_total_width():
	return (cards.size() * card_width) + ((cards.size() - 1) * card_spacing)

# Function to update the positions of the cards in the hand
func update_card_positions(ignore = -1):
	var total_width = calculate_total_width()
	start_x = -total_width / 2 + card_width / 2

	for i in range(cards.size()):
		if(i == ignore):
			continue
		var card = cards[i]
		if(card.is_dragging):
			continue
		# Still flying on the path: its position belongs to the flight, which lands it on calculate_card_position().
		if card.get_parent() != self:
			continue
		card.index = i
		card.rotation = Vector3.ZERO
		animate_card(card, calculate_card_position(i)) # Position relative to the Hand
		
		
func last_card_position():
	return start_x + (card_width + card_spacing)*cards.size()
	
	
func calculate_card_position(i):
	# start_x is only set by update_card_positions(), so before this zone has ever laid a card out it is null
	# and the arithmetic below fails with "Invalid operands 'Nil' and 'float'". The damage zoom asks for a slot
	# position to aim a camera at, and it can legitimately ask before the first card lands — so the fallback is
	# the row's own centre, which is where a single card would sit anyway. Without this, aiming at an empty
	# zone is a crash rather than a miss.
	var base: float = 0.0
	if start_x != null:
		base = float(start_x)
	elif card_width != null:
		base = -float(card_width) * 0.5
	var x_offset = base + i * (card_width + card_spacing)
	# A SMALL RISE PER CARD, so each new damage card lands visibly ON TOP of the previous one. It was 1 mm,
	# which is not enough to separate overlapping cards at this zoom: with the cards stepping 0.13 m apart and
	# drawn at 1.2x, the overlap edge was buried in the card behind it. 8 mm is still a gentle stack.
	var y_offset = (i) * 0.008
	# ONE STRAIGHT ROW: every card on the zone's own line, no sideways shift per card. (A per-card shift onto the deck's
	# screen column was tried; it slanted the row in the world and the stepped edges read as a zig-zag.)
	return Vector3(x_offset, y_offset, 0)
	
func remove_card(card):
	cards.remove_at(card.index)
	

		
func animate_card(card, target_position):
	# Create a Tween to animate the card's movement
	var tween = create_tween()
	tween.tween_property(card, "position", target_position, 0.15)

## CARD INPUT. A card in a pile is LOOKED AT, not played: clicking one opens the same fan window the deck search
## uses, so the player can check what is in the zone. The host is two levels up (pile -> Player -> Game) and it is
## duck-typed, so a pile mounted anywhere else simply does nothing rather than erroring.
func on_card_grabbed(_card: Card) -> void:
	if game != null and game.has_method("_show_zone_view"):
		game.call("_show_zone_view", self, "Damage Zone")
