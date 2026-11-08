extends Node3D

class_name Card
const LOG := preload("res://scripts/log.gd")
## Who controls a card. Plain strings (they come from the data and the match setup), named so a typo
## fails to parse instead of silently comparing false.
const PLAYER := "player"
const OPPONENT := "opponent"
## Card types, spelled as the card database spells them.
const FORWARD := "Forward"
const BACKUP := "Backup"
const SUMMON := "Summon"
const CRYSTAL_SCENE_PATH = "res://crystal.tscn"
const ELEMENTS := preload("res://scripts/elements.gd")
@export var id: int = 0  # Make this editable in the Inspector
var string_id: String = '0'
# Scale factor when hovered
# Original scale of the card
var original_scale: Vector3
var code: String
@export var power: int
@export var base_power: int
## Damage the card has accumulated this turn. The card breaks once this
## reaches its current power; it is reset to 0 during the End Phase.
@export var accumulated_damage: int = 0
var crystal_scene
var crystal_instance
var _stack_face: SubViewport
var _printed_texture: Texture2D
var mat: ShaderMaterial
@export var tapped = false;
@export var text = '';
@export var is_valid_target = false;
@export var cost: int
@export var is_dragging = false
## Set when a drag has already been ended, so the mouse-release signal and the
## per-frame button check cannot both run the drop logic.
var _drag_release_handled := false
## True only for a drag started by a real grab. The per-frame fallback uses it so
## code that merely sets is_dragging (tests, staging) is never auto-released.
var _drag_input_active := false
@export var selected = false
@export var type: String
@export var card_name: String
@export var index = 0
@export var controller = PLAYER
@export var element = ''
@export var status_effects = {}
@export var power_array = []
## CONTINUOUS POWER CONTRIBUTIONS, keyed by source (aura:<source id>:<index>, conditional:<card id>:<rule>, ...).
## `power` is a cache of base_power + these + power_array + _manual_power_delta; nothing outside recompute_power()
## should write it for a normal effect.
var _continuous_power: Dictionary = {}
## Legacy permanent deltas that were expressed as power_change(amount, -1) before the ledger existed.
var _manual_power_delta: int = 0
signal power_changed(value: int)
## Keywords GRANTED by a continuous effect (an aura), as opposed to printed in card_effects. A COUNT, not a bool,
## because two auras can grant the same keyword and losing one must not lose the other.
var granted_statuses: Dictionary = {}
## Extra attacks left this turn ("Gilgamesh can attack twice", Tidus' Blitz Ace). Consumed by Field.execute_card_attack.
var extra_attacks: int = 0
var _printed_effects: Dictionary = {}
## The card's effects as they are ACTIVE right now. "Loses all abilities" is a temporary, per-card view, never a
## change to the shared JSON data: while abilities_nullified is present every printed ability lookup sees an empty
## dictionary, and the original data comes back when the status expires.
const EFFECT_REGISTRY := preload("res://scripts/effects/effect_registry.gd")
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")
const TARGET_CONTEXT := preload("res://scripts/effects/target_context.gd")
const EVENTS := preload("res://scripts/effects/events.gd")
var _card_effect = null
var _elements_calculating: bool = false
## Auras granted to this card by another effect, or supplied by a test. Definitions are dictionaries or AuraSpecs.
var extra_auras: Array = []
@export var card_effects: Dictionary:
	get:
		return {} if status_effects.has("abilities_nullified") else _printed_effects
	set(value):
		_printed_effects = value
@export var key_word_effect: String
## A code-defined event on a stack copy. NONE for ordinary JSON effects and real cards.
var effect_event: int = EVENTS.Event.NONE
var effect_event_data: Dictionary = {}
## EVERY target this card's effect was given, in pick order. Most effects take one, and for those it is a one-element
## list; a card that says "choose up to 3" (Aerith 1-064) puts all of them here.
var effect_targets: Array[Card] = []
## The single target — which is what nearly every consumer wants. A PROPERTY over the list rather than a second field,
## so the two can never disagree: reading gives the LAST pick, and assigning replaces the whole list with that one card.
## Every existing `.effect_target` read and write therefore keeps working exactly as it did.
var effect_target: Card:
	get:
		return effect_targets.back() if not effect_targets.is_empty() else null
	set(value):
		effect_targets.clear()
		if value != null:
			effect_targets.append(value)

## Record a whole session's picks. Called by the Stack at pick time, so the EFFECT owns its targets from then on and
## nothing downstream has to read the targeting UI's state (which the next session overwrites).
func set_effect_targets(picks: Array) -> void:
	effect_targets.clear()
	for pick in picks:
		if pick != null and is_instance_valid(pick):
			effect_targets.append(pick)
@export var effect_source: Card
## Index into card_effects["skill"] for stack copies activating a skill (-1 = not used).
@export var skill_activation_index: int = -1
## The skill definition carried by a stack copy. Copied abilities use this instead of an index because the source
## card may overwrite its copy while this object is still on the stack.
var skill_def_override: Dictionary = {}
## The AbilitySpec snapshot of a code-defined activated ability. The stack proxy carries it so resolution can call the
## same handler even if the source card changes afterwards.
var ability_spec = null
## The X declared for an 《X》 ability, carried by the stack proxy so resolution uses the value that was actually paid.
## -1 means "not an X ability".
@export var ability_x_value: int = -1
## True when this stack copy is Kimahri's copied ability, so committing it can consume the permission.
var copied_skill_activation: bool = false
var copied_skill_token: int = 0
## "Summon" / "Ability" for stack copies; empty on real cards. Lets protection
## rules ("cannot be chosen by opponent's Summons or abilities") identify the
## source of a targeting effect.
@export var effect_kind: String = ""
## Board-wide event trigger carried by an EFFECT COPY on the stack. The copy is a normal Card (so it can be seen
## and responded to), but it resolves through Game._resolve_event_trigger instead of its own card data.
var event_trigger: Dictionary = {}
var event_context: Dictionary = {}
var _event_once: Dictionary = {}


## True the first time this key is claimed in `turn`, false afterwards. Used by once-per-turn event triggers.
func claim_event_once(key: String, turn: int) -> bool:
	var tag: String = "%s:%d" % [key, turn]
	if _event_once.has(tag):
		return false
	_event_once[tag] = true
	return true
## Power currently granted by conditional continuous effects (e.g. Zack/Aerith).
var current_conditional_bonus: int = 0
## KIMAHRI 1-102H. One copied Special Ability, not a library. Empty means no permission. The stack copy takes a
## snapshot, so this can be safely overwritten or cleared while an already-activated copy is still on the stack.
var copied_skill: Dictionary = {}
var copied_skill_from: String = ""

@onready var hand_mesh: MeshInstance3D = $HandMesh

var offset = Vector3.ZERO
var camera: Camera3D
var tween: Tween
## The hand's layout tween. It has to be killable: if a card is picked up while
## the fan is still animating, the old tween would keep writing a hand-local
## position into the card AFTER it has been reparented to the Stack.
var hand_tween: Tween
## The Stack's layout tween, kept per card for the same reason as `hand_tween`:
## if the card leaves the stack while the fan is still moving, the old tween must
## be stopped or it keeps writing stack-local positions into the new zone.
var stack_tween: Tween
## TELEPORT CAST presentation (source shine/fade, destination materialise). See card_teleport.gd.
const CARD_TELEPORT := preload("res://scripts/card_teleport.gd")
var teleport: CARD_TELEPORT = CARD_TELEPORT.new(self)
## Silence bubble + Frozen rim. See card_status_overlays.gd.
const CARD_STATUS_OVERLAYS := preload("res://scripts/card_status_overlays.gd")
var overlays: CARD_STATUS_OVERLAYS = CARD_STATUS_OVERLAYS.new(self)
## Last status set reported to Vfx. `refresh_status_visuals()` is the one sync
## point, so direct dictionary erases still produce a status_removed event.
var _vfx_status_snapshot: Dictionary = {}
@onready var power_label: Label3D =  $PowerDisplay
signal card_dragged(card)
signal focus_card(card)
signal execute_instructions(instructions)

func create_instruction_from_json(array: Array) -> Array[Instruction]:
	# Extract fields from JSON
	var ans: Array[Instruction] = []
	for json_instruction in array:
		var action: String = json_instruction.get("name", "")
		var executor: String = json_instruction.get("author", "")
		var value = json_instruction.get("argument", null)
		var condition: String = json_instruction.get("condition", "")
		var may_use: bool = bool(json_instruction.get("may", false))
		var may_by: String = str(json_instruction.get("may_by", ""))
		var may_prompt: String = str(json_instruction.get("may_prompt", ""))
		ans.append(Instruction.new(action, executor, value, condition, may_use, may_by, may_prompt))
	
	# Create and return the Instruction
	return ans

func _ready():
	camera = get_viewport().get_camera_3d()
	crystal_scene = load(CRYSTAL_SCENE_PATH)
	_build_target_border()
	CARD_EDGE.install(self, _card_face_size())

## Card thickness (a shared rounded-prism side wall). See card_edge.gd.
const CARD_EDGE := preload("res://scripts/card_edge.gd")

func initialize(card_id: int, card_controller: String):
	id = card_id
	string_id = str(card_id)
	controller = card_controller
	load_card_data()
	load_card_effects()
	assign_card_texture()
		
func load_card_data():
	var card_data = CardDatabase.card_database[id-1]
	if card_data:
		type = card_data.get('type_en','Unknown type')
		card_name = card_data.get("name_en", "Unknown")
		base_power = int(card_data.get("power", 0))
		_continuous_power.clear()
		power_array.clear()
		_manual_power_delta = 0
		power = base_power
		cost = int(card_data.get("cost", 0))
		code = card_data.get("code", "Unknown")
		text = card_data.get("text_en", "invalid")
		accumulated_damage = 0
		element = card_data.get("element",'invalid')[0]
		
	else:
		push_warning("Card with ID '%s' not found in database." % id)
		

func load_card_effects():
	if string_id in CardDatabase.card_effects:
		card_effects = CardDatabase.card_effects[string_id]
		
	
## False while the card is face-down. `mat` (the art material) is kept so that
## revealing restores the SAME instance — rebuilding it would drop the shader's
## `effect_enabled` highlight state.
var revealed: bool = true
var _card_back_material: StandardMaterial3D = null

## Show the card's art, or a plain back for a card whose identity is not public
## knowledge yet (a card parked while its cost is being paid). There is no back
## art asset, so the "back" is a flat dark material.
func set_revealed(is_revealed: bool) -> void:
	if revealed == is_revealed:
		return
	revealed = is_revealed
	var surface_material: Material = (mat as Material) if is_revealed else (_get_card_back_material() as Material)
	$HandMesh.set_surface_override_material(0, surface_material)
	$FieldMesh.set_surface_override_material(0, surface_material)

## Per-caster full silhouette data used by both hand and stack contact shadows.
func set_overlap_shadow(slot: int, world_to_caster: Transform3D, face: Vector2,
		radius: float, strength: float, softness: float, view_camera: Camera3D) -> void:
	if mat == null or slot < 0 or slot >= 4:
		return
	var prefix := "shadow_" if slot == 0 else "shadow%d_" % (slot + 1)
	mat.set_shader_parameter(prefix + "inverse", world_to_caster)
	mat.set_shader_parameter(prefix + "shape", Vector3(face.x * 0.5, face.y * 0.5, radius))
	mat.set_shader_parameter(prefix + "strength", clampf(strength, 0.0, 1.0))
	mat.set_shader_parameter(prefix + "width", maxf(softness, 0.0001))
	mat.set_shader_parameter("shadow_camera", view_camera.global_position)
	mat.set_shader_parameter("shadow_direction", view_camera.global_basis.z.normalized())
	mat.set_shader_parameter("shadow_orthographic", view_camera.projection == Camera3D.PROJECTION_ORTHOGONAL)

func clear_edge_shadow() -> void:
	if mat == null:
		return
	for prefix in ["shadow_", "shadow2_", "shadow3_", "shadow4_"]:
		mat.set_shader_parameter(prefix + "strength", 0.0)

## Hidden/inert staging for a REVEALED card: the card is out of the deck and in Game.revealed_cards, but it must not
## render or accept input until an effect moves it somewhere. The reverse is applied by enter_zone().
func set_hidden(hidden: bool) -> void:
	visible = not hidden
	process_mode = Node.PROCESS_MODE_DISABLED if hidden else Node.PROCESS_MODE_INHERIT
	var area: Node = get_node_or_null("CardArea3D")
	if area is CollisionObject3D:
		area.input_ray_pickable = not hidden

func _get_card_back_material() -> StandardMaterial3D:
	if _card_back_material == null:
		_card_back_material = StandardMaterial3D.new()
		# A NORMAL GREY, not near-black. This was (0.10, 0.11, 0.16), which is fine for one card turning over during a
		# draw and reads as a black hole when a whole hand of them sits on screen — the opponent's five cards measured
		# #3f3f3f and covered 6% of the frame. It is meant to say "there is a card here, face down", and the rest of the
		# board's card-sized greys sit around 0.6.
		_card_back_material.albedo_color = Color(0.58, 0.60, 0.64)
		_card_back_material.roughness = 0.85
	return _card_back_material

func assign_card_texture():
	var texture_path = "res://assets/cards/%s.jpg" % code
	var full_texture = load(texture_path)
	if not full_texture:
		push_error("Failed to load texture for card: %s" % code)
		return

	var shader = load("res://shaders/card.gdshader")
	mat = ShaderMaterial.new()
	mat.shader = shader
	_printed_texture = full_texture
	mat.set_shader_parameter("texture_albedo", full_texture)
	mat.set_shader_parameter("effect_enabled", false)
	mat.set_shader_parameter("shadow_strength", 0.0)
	mat.set_shader_parameter("teleport_progress", 0.0)
	mat.set_shader_parameter("teleport_glow", 0.0)
	mat.set_shader_parameter("teleport_reveal", 1.0)
	mat.set_shader_parameter("teleport_block_depth", 7.0)
	mat.set_shader_parameter("teleport_block_stop_chance", 0.15)
	mat.set_shader_parameter("teleport_white_block_depth", 6.0)
	mat.set_shader_parameter("teleport_white_block_stop_chance", 0.22)
	
	
	$HandMesh.set_surface_override_material(0, mat)
	$FieldMesh.set_surface_override_material(0, mat)

		
func _process(_delta):
	if not is_dragging or not _drag_input_active:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# THE MOUSE-RELEASE SIGNAL IS NOT GUARANTEED. It comes from CardArea3D, which only sees the event while the
		# pointer is over the card, so a fast release or one just off the edge never arrives. End the drag here through
		# the same path the signal uses.
		release_drag()
		return
	if current_zone == Zone.HAND and controller == PLAYER:
		var owner_hand := get_parent()
		if owner_hand is Hand and owner_hand.update_character_drag(self, get_viewport().get_mouse_position()):
			return
	# Update object position to mouse position
	emit_signal("card_dragged", self)
	global_transform.origin = _get_mouse_3d_position_on_card_plane() + offset

## Start an interactive drag. Called by Hand.on_card_grabbed() when the pointer grabs a
## hand card; tests and staging that set is_dragging directly do not arm the
## per-frame release fallback.
func begin_drag() -> void:
	_drag_release_handled = false
	_drag_input_active = true
	is_dragging = true

## Finish a drag exactly once. Both the CardArea3D release signal and the
## per-frame mouse check can reach here; whichever is first owns the drop.
func release_drag() -> void:
	if not is_dragging or _drag_release_handled:
		_drag_input_active = false
		return
	_drag_release_handled = true
	_drag_input_active = false
	is_dragging = false
	var zone: Node = get_parent()
	if zone != null and zone.has_method("on_card_released"):
		zone.on_card_released(self)
			

		
func _get_mouse_3d_position_on_card_plane() -> Vector3:
	# Get mouse position
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Create a ray from camera through mouse position
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	
	# Define the card's plane using its normal and a point on the plane
	var card_global_transform = global_transform
	var card_normal = card_global_transform.basis.y  # Assuming the card's "up" vector defines the plane normal
	var card_center = card_global_transform.origin  # A point on the card's plane
	
	# Create a plane using the card's normal and a point on the plane
	var card_plane = Plane(card_normal, card_center)
	
	# Calculate intersection of the ray with the card's plane
	var intersection = card_plane.intersects_ray(ray_origin, ray_normal)
	
	if intersection:
		return intersection
	else:
		# Fallback: Return the card's current position if no intersection is found
		return card_center


	
func _notification(what):
	# Arriving on a Field refreshes the power readout and the board's continuous effects.
	if what == NOTIFICATION_PARENTED and get_parent() is Field:
		_updateUI()
		_executeAuraEffects()
		
func _updateUI():
	showPower()

## Auras have one path: Field.refresh_continuous_effects() scans the board and collects this card's auras. Nothing is
## registered on the card or the field, so there is nothing to unregister when it leaves.

func _executeAuraEffects():
	var field_node: Node = get_parent()
	if field_node != null and field_node.has_method("refresh_continuous_effects"):
		field_node.refresh_continuous_effects()

## CARD INPUT IS THE ZONE'S BUSINESS. A click, release or hover is forwarded to the card's parent zone (Hand, Field,
## Stack, Graveyard, DamageZone), which decides what it means there. A parent without the method simply ignores it.
func _on_card_area_3d_card_grabbed(_card: Variant):
	_drag_release_handled = false
	var zone: Node = get_parent()
	if zone != null and zone.has_method("on_card_grabbed"):
		zone.on_card_grabbed(self)

## Hover on the card's own area. The hand's LIFT is driven separately by HandMesh
## (mesh_instance_3d.gd); these handlers exist so a zone can react to the pointer being over a
## card. The stack uses it to put a hovered card's targeting on display. The FIELD uses it to show a
## readable preview: a battlefield card is small, and at board scale its text cannot be read at all.
##
## Duck-typed on purpose — asking the parent whether it offers the preview keeps this handler from
## depending on the Field's class name, and a card parented anywhere else simply does nothing.
func _on_card_area_3d_mouse_entered():
	# PAYING FOR MANA disables every card hover: the hand is a row of sources and the field is not
	# what the player is choosing between. The hand's own gate lives in Hand.set_hovered().
	if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.PAYING_COST:
		return
	var zone: Node = get_parent()
	if zone != null and zone.has_method("on_card_hovered"):
		zone.on_card_hovered(self, true)

func _on_card_area_3d_mouse_exited():
	var zone: Node = get_parent()
	if zone != null and zone.has_method("on_card_hovered"):
		zone.on_card_hovered(self, false)
	
func can_be_played():
	var player_mode = GlobalVariables.get_player_mode()
	if player_mode == GlobalVariables.Player_Mode.INSTANT_SPEED_TIME:
		return type == SUMMON
	if player_mode == GlobalVariables.Player_Mode.FREE:
		# Summons are always playable; a Character is only legal for the turn
		# player and only with an empty stack. Card keeps no game reference, so
		# ask the Hand it is in (its parent while in hand).
		if type == SUMMON:
			return true
		var owner_hand = get_parent()
		if owner_hand != null and owner_hand.has_method("can_play_character"):
			return owner_hand.can_play_character(self)
		return true
	return false
	
func is_on_field():
	return get_parent() is Field

func showPower():
	if(power_label == null):
		return
	if(type == FORWARD):
		power_label.visible = true
		mat.set_shader_parameter("effect_enabled", true)
	else:
		power_label.visible = false

## The power/damage readout is field-only information: a card in hand, deck,
## stack, damage zone or graveyard must never wear it.
func hide_power_display() -> void:
	if power_label != null:
		power_label.visible = false

## Where a card currently lives. Its whole presentation (scale, rotation baseline,
## which UI is shown) is derived from this, so there is ONE place deciding how a
## card looks — instead of every zone transition leaving the previous zone's
## transform, scale and readout on the card.
## REMOVED is appended, never inserted: the numbers are written into saved scenes and printed by probes, so existing
## values must not shift.
enum Zone { NONE, DECK, HAND, FIELD, STACK, GRAVEYARD, DAMAGE, REMOVED }

## Cards read correctly in this project when turned a half turn about Y relative
## to the identity frame. The Hand, Stack, Graveyard, Deck and FocusCard scene
## nodes all supply that themselves with a flipped basis (-1 on X and Z), so their
## cards keep a zero local rotation. **The Field does not** — it is a plain
## identity node — so its cards carry the half turn themselves; zeroing their
## rotation would put every field card upside down.
const READABLE_ROTATION := Vector3(0, PI, 0)

## The size a card is drawn at once it is legally ON THE STACK.
##
## Public because the HAND grows a hovered card to exactly this size (see the STACK entry below and Hand.set_hovered):
## a card played straight from the hand then lands on the stack at the size it is already drawn at, instead of
## popping. That only stays true while this and the table agree, so the table reads this constant.
##
## 1.0 is a SIZE CHOICE for the perspective board. The stack sits closer to the lens than the field,
## so 1.0 world renders around 1.25x a field card — big enough to read, small enough to sit in the
## board instead of reading as a UI overlay. The hand hover has its own HOVER_CARD_SCALE, and the stack's
## pose lives in the Stack node's "Stack Rotation" exports.
const STACK_CARD_SCALE := 1.0

## The Stack scene node's OWN scale (game.tscn). A card's `scale` is LOCAL to its container, so a world size written
## straight into it would come out 2.3x bigger than the number says.
## Every zone entry below means the WORLD size its cards are drawn at, and STACK divides this back out to keep that
## promise. The other containers are at or near 1 (Hand 1.0, DamageZone 1.0, Field 1.005). Deck (1.4), Graveyard (1.2)
## and FocusCard (4.5) have the same latent inconsistency; left alone because nothing has asked for their world size.
const STACK_CONTAINER_SCALE := 2.305

## Per-zone look. `rotation` is the card's LOCAL baseline for that zone (see
## READABLE_ROTATION: it depends on whether the container node is flipped).
## `power_ui` is the field readout (Forward power + accumulated damage). A zone's
## layout code may still add rotation on top of this baseline — the hand fan adds
## its per-card tilt — but it starts from here.
##
## `scale` is the size a card is drawn at in that zone, and this table is the only
## place either number lives. The two that matter are HAND and STACK: the hand has its own
## resting and hover sizes (Hand.HOVER_CARD_SCALE), and the stack is drawn at 1.2 in WORLD,
## the same as a field card, so a played card does not jump to an enlarged size under the
## perspective camera.
## Deck, graveyard and removed piles are parented to nodes scaled 1.4 (see game.tscn), while a
## field card is 1.2 in WORLD. `scale` in this table is LOCAL, so a pile card has to carry
## 1.2 / 1.4 or it is drawn 17% larger than the cards on the board — which is exactly how the
## deck and graveyard ended up looking oversized.
const PILE_LOCAL_SCALE := 1.2 / 1.4

const ZONE_PRESENTATION := {
	Zone.NONE:      {"scale": 1.0, "rotation": Vector3.ZERO,      "power_ui": false},
	Zone.DECK:      {"scale": PILE_LOCAL_SCALE, "rotation": Vector3.ZERO, "power_ui": false},
	# HAND is the RESTING size of a fan card, and Hand lays the fan out for it. Under the perspective rig the hand is
	# 6.2 m from the camera and magnified by proximity; this keeps it readable while still larger than a field card.
	Zone.HAND:      {"scale": 1.35, "rotation": Vector3.ZERO,     "power_ui": false},
	Zone.FIELD:     {"scale": 1.2, "rotation": READABLE_ROTATION, "power_ui": true},
	# Divided by the container's own scale, because `scale` is LOCAL: the card has to end up at STACK_CARD_SCALE in the
	# WORLD. See STACK_CONTAINER_SCALE.
	Zone.STACK:     {"scale": STACK_CARD_SCALE / STACK_CONTAINER_SCALE, "rotation": Vector3.ZERO, "power_ui": false},
	Zone.GRAVEYARD: {"scale": PILE_LOCAL_SCALE, "rotation": Vector3.ZERO, "power_ui": false},
	# Removed from the game looks exactly like the Break Zone: a plain untilted card with no readout. It gets its own
	# zone value so the viewer can tell the two piles apart and so nothing can "leave the Break Zone" out of it.
	Zone.REMOVED:   {"scale": PILE_LOCAL_SCALE, "rotation": Vector3.ZERO, "power_ui": false},
	# TODO: the damage-zone node is identity like the Field, so by this rule it
	# needs READABLE_ROTATION too. Left alone until it can be eyeballed, because
	# the OPPONENT's damage zone is authored with a +90 deg frame instead.
	Zone.DAMAGE:    {"scale": 1.2, "rotation": Vector3.ZERO,      "power_ui": false},
}

var current_zone: Zone = Zone.NONE

## Put the card back to its current zone's resting size.
##
## Kept apart from enter_zone() because a drag that ends with the card staying in the SAME zone only needs its size
## restored — re-running the whole zone transition would also drop the target glow and the mana crystal.
func apply_zone_scale() -> void:
	var presentation: Dictionary = ZONE_PRESENTATION.get(current_zone, ZONE_PRESENTATION[Zone.NONE])
	scale = Vector3.ONE * float(presentation["scale"])

## The tween currently sizing this card, so a second request cancels the first rather than fighting it.
var _size_tween: Tween = null

## Grow or shrink to `to_scale` over `seconds`. Used by the hand's hover, which takes a card to the size it will be on
## the stack.
##
## It lives here because the card's scale is the card's — and it is PER CARD rather than one tween owned by the hand,
## because hovering across a hand cancels the outgoing card's shrink as well as the incoming card's growth, and one
## shared tween would leave one of them stranded part-way.
func tween_to_scale(to_scale: float, seconds: float) -> void:
	if _size_tween != null and _size_tween.is_valid():
		_size_tween.kill()
	if seconds <= 0.0 or not is_inside_tree():
		scale = Vector3.ONE * to_scale
		return
	_size_tween = create_tween()
	_size_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_size_tween.tween_property(self, "scale", Vector3.ONE * to_scale, seconds)

## The ONE entry point for a zone change. Call it as soon as the card has been
## reparented and BEFORE the destination lays it out: it normalises rotation and
## scale, drops every transient marker (drag, target glow, mana crystal) and shows
## or hides the field readout. Positions stay the zone's own business.
func enter_zone(zone: Zone, stack_wording: String = "") -> void:
	if zone == Zone.STACK and _stack_face == null:
		_stack_face = preload("res://stack_ability_face.tscn").instantiate()
		add_child(_stack_face)
		_stack_face.configure(_printed_texture, element, stack_wording if not stack_wording.is_empty() else text)
		mat.set_shader_parameter("texture_albedo", _stack_face.get_texture())
	elif zone != Zone.STACK and _stack_face != null:
		mat.set_shader_parameter("texture_albedo", _printed_texture)
		remove_child(_stack_face)
		_stack_face.queue_free()
		_stack_face = null
	# A zone change is not a teleport in progress: normal cards must always be
	# fully opaque. The teleport path sets progress back to 1 immediately after
	# entering the field, while the card is still invisible.
	teleport.reset()
	# A hit reaction must not survive a zone change. It is a mesh-local tween,
	# so without this the card could arrive in the hand/Graveyard still lifted
	# and tilted.
	damage_fx.normalize()
	# Leaving the stack must stop the fan tween HERE. Otherwise a tween created
	# while the card was parked keeps writing Stack-local positions after the card
	# has been reparented to the hand or the field, and the new zone's layout
	# appears to "stick" until the next manual reorder.
	if current_zone == Zone.STACK and zone != Zone.STACK:
		stop_stack_layout()
	# A copied ability is a continuous effect while its source is on the field. Leaving the field drops it.
	if current_zone == Zone.FIELD and zone != Zone.FIELD:
		clear_copied_skill()
	current_zone = zone
	set_hidden(false)
	var presentation: Dictionary = ZONE_PRESENTATION.get(zone, ZONE_PRESENTATION[Zone.NONE])
	# Local rotation: NOT always zero — see READABLE_ROTATION. The Field is an
	# unflipped container, so its cards must carry the half turn themselves.
	rotation = presentation["rotation"]
	# The pose a tap animates away from and comes back to. Recorded HERE because this is the single place a card's resting
	# orientation is decided; tap()/untap() aim at this absolute angle instead of offsetting whatever they find.
	_upright_y = rotation_degrees.y
	apply_zone_scale()
	is_dragging = false
	_drag_input_active = false
	is_valid_target = false
	# EVERY meaning of the ring is about a card in its CURRENT zone: the prompt, "you picked
	# this", "they picked this", "you may activate this", "mana was spent on this", and
	# "this Character is waiting to be played". Leaving any of them set would carry the ring
	# into the next zone — a red or a green one into the graveyard, white onto the field.
	_prompt_glow = false
	_selected_highlight_on = false
	_s_cost_highlight_on = false
	_targeted_highlight_on = false
	_available_highlight_on = false
	_energized_highlight_on = false
	_cast_pending_highlight_on = false
	_refresh_target_ring()
	clear_edge_shadow()
	reset()  # drops the mana-crystal marker
	if bool(presentation["power_ui"]):
		showPower()
	else:
		hide_power_display()
	refresh_status_visuals()
		
@export var tap_speed: float = 0.3
@export var tap_angle: float = -15.0

## The y rotation this card holds when it is NOT tapped. Set on entering a zone, because that is the one place a card's
## resting orientation is decided — so tap()/untap() always have an absolute angle to aim at.
var _upright_y: float = 0.0

func tap():
	if tapped: return
	
	tapped = true
	
	if tween != null and tween.is_valid():
		tween.kill()
	
	# AN ABSOLUTE ANGLE, NOT "the tap angle from wherever it happens to be": a relative tween killed mid-flight (an
	# activation undone immediately) would leave the card part-way round, and repeated tap/untap would walk it around.
	# The angle is a SMALL tilt (15°): a tapped card only needs to read as "resting", and a quarter turn would put its
	# art and stats sideways on a board seen in perspective.
	tween = create_tween()
	tween.tween_property(self, "rotation_degrees:y", _upright_y + tap_angle, tap_speed)

func untap():
	if not tapped: return
	
	tapped = false
	
	if tween != null and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.tween_property(self, "rotation_degrees:y", _upright_y, tap_speed)

## Stop the hand's layout tween before another zone takes ownership of the card.
func stop_hand_layout() -> void:
	if hand_tween != null and hand_tween.is_valid():
		hand_tween.kill()
	hand_tween = null

## Stop the Stack's layout tween before another zone takes ownership of the card.
func stop_stack_layout() -> void:
	if stack_tween != null and stack_tween.is_valid():
		stack_tween.kill()
	stack_tween = null

## Damage presentation (recoil + Earth launch). See card_damage_fx.gd.
const CARD_DAMAGE_FX := preload("res://scripts/card_damage_fx.gd")
var damage_fx: CARD_DAMAGE_FX = CARD_DAMAGE_FX.new(self)

## WHO/WHAT dealt the most recent damage. The state-based break happens later, in a sweep that cannot see the source,
## so the damage records it here and the sweep asks the same protection question an explicit break does.
## An empty kind means COMBAT damage — nobody's Summon or ability — which is also what clears a stale record.
##
## `source_card` is the DEALING card (Warrior of Light doubles damage he deals). It is separate from the kind: combat
## passes the opposing card, a character ability passes the character, a Summon passes the Summon.
var last_damage_kind: String = ""
var last_damage_controller: String = ""
var last_damage_source: Card = null

func suffer_damage(damage: int, source_kind: String = "", source_controller: String = "",
		source_card: Card = null, reaction_delay: float = 0.0):
	# Damage accumulates; the card breaks once the total reaches its current
	# power (enforced by Game.enforce_game_state_rules()).
	last_damage_kind = source_kind
	last_damage_controller = source_controller
	last_damage_source = source_card
	accumulated_damage += damage
	if power_label:
		power_label.changeAccumulatedDamage(accumulated_damage)
	# COMBAT damage is the empty kind. Effect/Summon damage gets the reaction;
	# combat has its own clash presentation.
	if damage > 0 and is_on_field() and not source_kind.is_empty():
		if not Vfx.owns_damage_reaction(source_card):
			damage_fx.play_reaction(damage, reaction_delay)

func take_damage(damage: int, source_kind: String = "", source_controller: String = "",
		source_card: Card = null, reaction_delay: float = 0.0):
	# Alias kept for effect data that uses the "take_damage" instruction.
	suffer_damage(damage, source_kind, source_controller, source_card, reaction_delay)


func is_broken() -> bool:
	# Break rule: accumulated damage equal to or greater than current power.
	return accumulated_damage >= power
	
## TRUE WHEN THIS CARD BROKE (damage reached its power), false when it merely left play. Set by whoever moves it,
## read and cleared by the Break Zone once the card has ARRIVED — the trigger fires from the pile, not from the
## field, because a card has not "been put into the Break Zone" until it is actually there.
var broken: bool = false

func has_zero_power() -> bool:
	# Power of 0 or less is NOT a break: the card is put into the Graveyard.
	return power <= 0

func clear_damage():
	# End Phase cleanup: all damage is removed from the card.
	accumulated_damage = 0
	if power_label:
		power_label.changeAccumulatedDamage(0)

## A CARD COMING BACK FROM A NON-FIELD ZONE IS A NEW OBJECT: no damage, no statuses, no leftover buffs, untapped,
## not broken. `power` is a running value, so temporary buffs have to be SUBTRACTED before their list is dropped —
## clearing power_array alone would leave the bonus baked into `power` forever.
func reset_for_field_arrival() -> void:
	# A card returning from a non-field zone is a new object. Drop every modifier, then recompute once; there is no
	# arithmetic to reverse because `power` is only a cache.
	damage_fx.normalize()
	_continuous_power.clear()
	power_array.clear()
	_manual_power_delta = 0
	status_effects.clear()
	granted_statuses.clear()
	refresh_status_visuals()
	extra_attacks = 0
	clear_damage()
	broken = false
	untap()
	recompute_power()

## A status is a duration (int) or a payload Dictionary with a "duration" inside. The optional `payload` form is how
## a one-shot damage rule is carried: {"operation": "set", "value": 0} or {"operation": "subtract", "value": 2000}.
## The pipeline does not know the status NAME; it reads any payload that has operation/value and consumes it
## (unless once is false), and turn_end() expires it like any other status.
func add_status_effect(status, duration, payload: Dictionary = {}):
	if duration is Dictionary:
		var entry: Dictionary = duration.duplicate()
		entry.merge(payload, true)
		status_effects[status] = entry
	else:
		if payload.is_empty():
			status_effects[status] = duration
		else:
			var entry: Dictionary = payload.duplicate()
			entry["duration"] = duration
			status_effects[status] = entry
	refresh_status_visuals()

## Continuous GRANTS (an aura), as opposed to timed statuses. Counted so two sources can grant the same keyword and
## one leaving does not revoke the other's.
func grant_status(status: String) -> void:
	granted_statuses[status] = int(granted_statuses.get(status, 0)) + 1

func revoke_status(status: String) -> void:
	var n: int = int(granted_statuses.get(status, 0)) - 1
	if n > 0:
		granted_statuses[status] = n
	else:
		granted_statuses.erase(status)

func has_granted(status: String) -> bool:
	return int(granted_statuses.get(status, 0)) > 0

## True when this card is marked "must block" for one of the attackers (the attacker, or every member of a party).
## The marker stores the source's instance id, because "must block Lightning" is not the same as "must block the
## current attacker": another Forward attacking must not consume the obligation.
func must_block_against(attackers: Array) -> bool:
	if not status_effects.has("must_block"):
		return false
	var payload = status_effects["must_block"]
	if not (payload is Dictionary):
		return false
	var source_id: int = int(payload.get("source_id", 0))
	if source_id == 0:
		return false
	for attacker in attackers:
		if attacker != null and is_instance_valid(attacker) and attacker.get_instance_id() == source_id:
			return true
	return false

## "Double the power of this Forward until the end of the turn." A one-time doubling at resolution: if power later
## changes, the doubled value is the base it happened on, which is what the rules mean.
func double_power(duration: int = 1) -> void:
	power_change(power, duration)

## "Can attack twice this turn": extra attacks are consumed by Field.execute_card_attack, which skips the tap while
## one remains.
func set_extra_attacks(count: int) -> void:
	extra_attacks = maxi(0, count)

func turn_end():
	# Kimahri's copied ability, like everything else temporary, expires at end of turn.
	clear_copied_skill()
	# End Phase cleanup for this card: expire "until end of turn" status
	# effects and temporary power modifiers, then remove all damage.
	for s in status_effects.keys():
		# FROZEN IS NOT A COUNTDOWN. It is spent by the Active Phase it denies (Field.untap_cards_for), and the
		# Active Phase comes before its controller's End Phase — so decrementing it here could only ever remove it
		# early, never late. Any number stored for it is a formality; skipping it keeps that from being load-bearing.
		#
		# `skip_next_active` (Kain: "will not activate during your next Active Phase") works the same way and is
		# consumed by the same untap, for the same reason.
		if s == "frozen" or s == "skip_next_active":
			continue
		var dur = status_effects[s]
		# JSON NUMBERS ARRIVE AS FLOAT. `dur is int` is false for a duration parsed out of card_effects.json, so a
		# status applied from card data never decremented and never expired — Red Mage's block_disabled, for one,
		# was permanent. Both numeric kinds count down; anything else (a marker with no number) is left alone.
		if dur is int or dur is float:
			var left: int = int(dur) - 1
			if left <= 0:
				status_effects.erase(s)
			else:
				status_effects[s] = left
		elif dur is Dictionary:
			# A STATUS WITH A PAYLOAD. "This Forward that took damage from Cid" carries the trigger that must run if it
			# leaves the field, and it still has to expire at end of turn like any other status.
			var left: int = int(dur.get("duration", 0)) - 1
			if left <= 0:
				status_effects.erase(s)
			else:
				dur["duration"] = left

	refresh_status_visuals()
	var remaining_buffs: Array = []
	for p in power_array:
		var dur = p[1]
		# Same float trap: "+1000 until end of turn" from the card data is a duration of 1.0, so an `is int` test
		# would skip it and the power would never come back down.
		if (dur is int or dur is float) and int(dur) > 0:
			var left: int = int(dur) - 1
			if left > 0:
				p[1] = left
				remaining_buffs.append(p)
		else:
			# Permanent entries in power_array are legacy; new continuous effects live in _continuous_power.
			remaining_buffs.append(p)
	power_array = remaining_buffs
	recompute_power()
	# "can attack twice THIS turn" - the allowance expires with the turn, not with the card.
	extra_attacks = 0
	clear_damage()
	
			
## "Its power becomes 1000" (Wakka 216): a temporary SET, expressed as the delta from the current value. Keeping it
## in power_array means existing temporary modifiers still expire correctly and a later +X applies on top.
func set_power_value(value: int, duration: int = 1) -> void:
	power_change(value - power, duration)


## The one place that computes the displayed/current power. It never changes base_power, and it is safe to call as
## often as a board refresh needs to; the signal only fires when the number actually changes.
## Test/setup hook: change the printed base and recompute from it. Production card data sets base_power during load.
func set_base_power(value: int) -> void:
	base_power = value
	recompute_power()


func recompute_power() -> void:
	var next: int = base_power + _manual_power_delta
	for amount in _continuous_power.values():
		next += int(amount)
	for buff in power_array:
		if buff is Array and not buff.is_empty():
			next += int(buff[0])
	if next == power:
		return
	power = next
	if power_label:
		power_label.changePower(power)
	power_changed.emit(power)


## Register/revoke a continuous contribution. The key names the OWNER of the effect, so two auras on one target sum
## independently and revoking one cannot remove the other's amount.
func add_power_modifier(key: String, amount: int) -> void:
	if key.is_empty():
		return
	_continuous_power[key] = int(amount)
	recompute_power()


func remove_power_modifier(key: String) -> void:
	if _continuous_power.erase(key):
		recompute_power()


func power_change(amount, duration):
	if int(amount) == 0:
		return
	if duration == null:
		duration = -1
	if int(duration) > 0:
		power_array.append([int(amount), duration])
	else:
		_manual_power_delta += int(amount)
	recompute_power()
	
## Skills the card can actually activate right now: printed skills plus Kimahri's copied ability.
func activation_skills() -> Array:
	if not abilities_enabled():
		return []
	var out: Array = []
	# CODE-DEFINED ABILITIES WIN over the JSON list for the same card, so a card can migrate its abilities without
	# keeping a duplicate set in card_effects.json.
	var effect_obj = effect()
	if effect_obj != null and effect_obj.has_method("activated_abilities"):
		for spec in effect_obj.activated_abilities():
			if spec != null and spec.has_method("as_skill_dict"):
				out.append(spec.as_skill_dict())
	if not out.is_empty():
		if not copied_skill.is_empty():
			out.append(copied_skill)
		return out
	var printed = card_effects.get("skill", [])
	if printed is Array:
		out.append_array(printed)
	if not copied_skill.is_empty():
		out.append(copied_skill)
	return out


## One skill by index in activation_skills(). Used by the existing index-based activation pipeline.
func activation_skill(skill_index: int) -> Dictionary:
	var skills: Array = activation_skills()
	if skill_index < 0 or skill_index >= skills.size() or not (skills[skill_index] is Dictionary):
		return {}
	return skills[skill_index]


## The code-defined AbilitySpec behind one activation slot, if it has one. JSON abilities return null and keep using
## their instruction list.
func activation_ability_spec(skill_index: int) -> RefCounted:
	var definition: Dictionary = activation_skill(skill_index)
	if definition.has("_ability_spec"):
		return definition["_ability_spec"]
	return null


## Only Special Abilities (the ones with an S icon / s_cost) are valid Ronso Rage targets.
func special_ability_skills() -> Array:
	var out: Array = []
	for def in activation_skills():
		if def is Dictionary and (bool(def.get("s_cost", false)) or bool(def.get("special_ability", false))):
			out.append(def)
	return out


## Criteria predicate for "choose 1 Forward opponent controls that has a Special Ability".
func has_special_ability(want: bool = true) -> bool:
	return (not special_ability_skills().is_empty()) == want


## Install a copied Special Ability. The source text is kept, but every activation cost is stripped. The "only if"
## restrictions and the effect instructions stay: they are not costs.
func set_copied_skill(definition: Dictionary, from_name: String = "") -> void:
	if definition.is_empty():
		return
	var copy: Dictionary = definition.duplicate(true)
	for key in ["cost", "tap", "s_cost", "discard", "sacrifice"]:
		copy.erase(key)
	copy["copied"] = true
	copy["special_ability"] = true
	copy["free_activation"] = true
	copy["copied_from"] = from_name
	copied_skill = copy
	copied_skill_from = from_name
	copied_skill_token += 1


func clear_copied_skill() -> void:
	if copied_skill.is_empty() and copied_skill_from == "":
		return
	copied_skill = {}
	copied_skill_from = ""
	copied_skill_token += 1


## Consume exactly the permission this stack copy was made from. A newer Ronso Rage may have overwritten the slot
## before this activation commits, and that newer permission must not be consumed by the older activation.
func consume_copied_skill(token: int) -> void:
	if token != 0 and token == copied_skill_token:
		clear_copied_skill()


func get_card_effect_instructions() -> Array[Instruction]:
	if key_word_effect == "skill":
		if not skill_def_override.is_empty():
			return create_instruction_from_json(skill_def_override.get("instructions", []))
		if skill_activation_index >= 0:
			if not "skill" in card_effects:
				push_error(str("No skill entry for card ", id))
				return []
			var skills = card_effects["skill"]
			if skill_activation_index >= skills.size():
				return []
			var raw = skills[skill_activation_index].get("instructions", [])
			return create_instruction_from_json(raw)
	if key_word_effect != "" and key_word_effect in card_effects:
		var entry = card_effects[key_word_effect]
		if entry is Dictionary and entry.has("instructions"):
			return create_instruction_from_json(entry["instructions"])
		if entry is Array and entry.size() > 0:
			var first = entry[0]
			if first is Dictionary and first.has("instructions"):
				return create_instruction_from_json(first["instructions"])
	push_error("No keyword %s in card effects" % key_word_effect)
	return []
func is_key_word_in_card_effect(keyword:String):
	return keyword in card_effects
	
	
		
func declare_blocker():
	# Only records the blocker. The clash belongs to DAMAGE_RESOLUTION — doing it
	# here as well would apply the damage twice.
	var instructions: Array[Instruction] = [
		Instruction.new('set_blocker','game', self),
	]
	emit_signal("execute_instructions", instructions)

## "Loses all abilities" (Wakka 216). This is a read-time view, not a mutation of the printed data. A status is
## cleared by turn_end like every other until-end-of-turn effect, and stack copies keep their own snapshots.
func abilities_enabled() -> bool:
	return not status_effects.has("abilities_nullified")

## Every card-space status visual in one place. Callers that mutate
## `status_effects` directly (or erase a status in place, as the Active Phase
## does for Freeze) use this to re-sync the visuals.
func refresh_status_visuals() -> void:
	_sync_status_vfx()
	overlays.refresh()

## Report status additions/removals through the presentation director. This is
## the one place that notices direct dictionary erases too, because every
## status mutation already calls refresh_status_visuals().
func _sync_status_vfx() -> void:
	var current: Dictionary = status_effects.duplicate()
	for status in current:
		if not _vfx_status_snapshot.has(status):
			Vfx.status_applied(self, str(status), _status_duration(status))
	for status in _vfx_status_snapshot:
		if not current.has(status):
			Vfx.status_removed(self, str(status))
	_vfx_status_snapshot = current


func _status_duration(status: String) -> int:
	var value = status_effects.get(status, 0)
	if value is Dictionary:
		return int(value.get("duration", 0))
	if value is int or value is float:
		return int(value)
	return 0

## PRINTED Haste comes from card_effects.json ("haste": true); GRANTED Haste is a status named "haste". Kept
## separate on purpose, exactly like cannot_be_chosen: the card's data says what it always has, the status says
## what something gave it, and anything asking "can this tap" needs one answer.
## Which event an EX BURST runs. Code wins; JSON is the fallback for the handful of cards not yet migrated.
func ex_burst_event() -> int:
	var effect_obj = effect() if abilities_enabled() else null
	if effect_obj != null and effect_obj.has_method("ex_burst_event"):
		var code_event: int = int(effect_obj.ex_burst_event())
		if code_event != EVENTS.Event.NONE:
			return code_event
	return EVENTS.from_name(str(card_effects.get("ex_burst", "")))


func has_haste() -> bool:
	return card_effects.has("haste") or status_effects.has("haste") or has_granted("haste") 		or has_code_keyword("haste")



func has_code_keyword(keyword: String) -> bool:
	var effect_obj = effect() if abilities_enabled() else null
	return effect_obj != null and keyword in effect_obj.keywords()

## BRAVE: attacking does not dull this card, so it can attack and still block (or attack again). Same split as
## Brave — printed "brave": true in card_effects.json, granted as a status named "brave", or granted by a party effect
## on the field ("The Forwards forming a party you control gain Brave", Gippal). The Field is the only thing that knows
## who is currently in a party, so it is asked rather than duplicating the rule here.
func is_brave() -> bool:
	if card_effects.has("brave") or status_effects.has("brave") or has_granted("brave") 			or has_code_keyword("brave"):
		return true
	var host: Node = get_parent()
	return host != null and host.has_method("party_grants_brave") and host.call("party_grants_brave", self)

## FIRST STRIKE: this card deals its damage before a card without it. Printed "first_strike": true, or granted as
## a status of the same name. The two-step combat itself lives in Game.clash_attacker_blocker() — this only answers
## the question it asks.
func is_first_strike() -> bool:
	return card_effects.has("first_strike") or status_effects.has("first_strike") or has_granted("first_strike") 		or has_code_keyword("first_strike")

## FROZEN: does not activate during its controller's next Active Phase. Granted only - no card prints Freeze, they
## all say "Freeze it" - so unlike Haste, Brave and First Strike there is no printed half. The status is CONSUMED
## by the Active Phase untap it denies (see Field.untap_cards_for), not counted down in turn_end().
func is_frozen() -> bool:
	return status_effects.has("frozen")

## CAN THIS CARD BE TAPPED AT ALL? Summoning sickness stops it, Haste ignores it, and an already-tapped card is
## obviously out. EVERY cost that taps must ask THIS rather than reading `tapped` — attacking, and any skill with
## a tap cost — or a card that entered this turn gets to act.
func can_tap() -> bool:
	if tapped:
		return false
	if status_effects.has("summoning_sickness") and not has_haste():
		return false
	return true

func can_attack():
	if not can_tap():
		return false
	# "IT CANNOT ATTACK THIS TURN" is a separate restriction from cannot-tap: the card may still be dulled to pay
	# costs, it just may not declare an attack. Checking it here (rather than inside can_tap) keeps the two apart,
	# and every consumer — the click handler, the AI's attacker pick, the attack button — already goes through this.
	if status_effects.has("cannot_attack"):
		return false
	if(type != FORWARD):
		return false
	return true

## Can THIS card, as the ATTACKER, be blocked by `blocker`? One side of the blocking legality — attacker-side
## restrictions like Yuffie's "cannot be blocked by a Forward of cost 4 or more".
##
## Data: "cannot_be_blocked_by": {"min_cost": 4} or {"greater_power": true}.
func allows_blocker(blocker: Card) -> bool:
	if blocker == null:
		return false
	var effect_obj = effect() if abilities_enabled() else null
	return effect_obj == null or effect_obj.allows_blocker(self, blocker)

## The other side: can THIS card, as the BLOCKER, legally block `attacker`? Lann also cannot block a Forward with
## greater power than his own. Data: "cannot_block": {"min_cost": n} or {"greater_power": true}.
func can_block_attacker(attacker: Card) -> bool:
	if attacker == null:
		return true
	var effect_obj = effect() if abilities_enabled() else null
	return effect_obj == null or effect_obj.can_block_attacker(self, attacker)
		
func attack():
	tap()
	
func get_cost() -> Dictionary:
	return {element:1, "neutral":cost-1}

func get_cast_target_criteria() -> Variant:
	# Targeting requirement for casting (Summons use "when_cast").
	# A Dictionary is one stage; an Array is several, asked in order (Hades: Forward, then Backup).
	# CODE FIRST. A migrated Summon owns its cast timing here; the JSON branch remains only for the cards still
	# waiting for their code pass.
	var effect_obj = effect() if abilities_enabled() else null
	if effect_obj != null and effect_obj.has_method("cast_target_criteria"):
		var code_criteria = effect_obj.cast_target_criteria(make_effect_context("cast"))
		if code_criteria is Object and code_criteria.has_method("to_legacy"):
			return code_criteria.to_legacy()
		if code_criteria is Dictionary:
			return code_criteria
		if code_criteria is Array:
			return code_criteria
	if "when_cast" in card_effects:
		var entry = card_effects["when_cast"]
		if entry is Dictionary and entry.has("choose_target"):
			var criteria = entry["choose_target"]
			if criteria is Dictionary or criteria is Array:
				return criteria
	return {}

## "Selected as a mana source" marker. Owned here so that every selection path —
## the human's clicks and an agent paying a cost — produces the same marker.
func show_mana_crystal() -> void:
	if crystal_instance != null or crystal_scene == null:
		return
	crystal_instance = crystal_scene.instantiate()
	add_child(crystal_instance)
	crystal_instance.position = Vector3(0, 0.05, -0.35)

func clear_mana_crystal() -> void:
	if crystal_instance == null:
		return
	crystal_instance.queue_free()
	crystal_instance = null

func reset():
	clear_mana_crystal()

func _on_card_area_3d_card_released(_card: Variant) -> void:
	release_drag()
		
## Glow ring marking a card the game is asking the player to choose or target.
## ALL of the look lives in shaders/target_border_material.tres — open it in the
## editor to tune colours, thickness and pulse from the Inspector. Card itself
## only supplies `card_size` (read from the mesh) and drives `intensity`.
const TARGET_BORDER_MATERIAL := preload("res://shaders/target_border_material.tres")
var target_border: MeshInstance3D = null
var _border_material: ShaderMaterial = null
var _border_tween: Tween = null
var _highlight_on: bool = false

## `glow` exists because legality and visibility are not the same thing. `is_valid_target`
## gates the local player's clicks and is what an agent looks for; the blue ring means "the
## game is asking YOU". When the OPPONENT is the one choosing, the flag must still be set
## (their agent needs it) but the ring is suppressed — we show only the card they actually
## pick, in red.
func set_valid_target(value: bool, glow: bool = true):
	is_valid_target = value
	set_prompt_glow(value and glow)

## The card the player has actually PICKED (the current target, or the card chosen
## for an effect): the same ring in a different colour, so the orange one obviously
## means "this one" while the blue ones are merely legal.
const SELECTED_BORDER_COLOR := Color(1.0, 0.45, 0.05)
const SELECTED_GLOW_COLOR := Color(0.95, 0.32, 0.0)
## The card the OPPONENT has chosen. Their legal options are not our business, so this is
## the only cue we get about an incoming effect while it is still on the stack — drawn in
## red, alongside their targeting arc.
const TARGETED_BORDER_COLOR := Color(0.95, 0.12, 0.12)
const TARGETED_GLOW_COLOR := Color(0.85, 0.03, 0.03)
## A card whose effect YOU can activate right now: an untapped Backup with a "skill", in a
## moment where acting is allowed. Green means "this is available", not "this is being chosen"
## — it goes dark the instant a targeting or payment modal takes the moment away.
const AVAILABLE_BORDER_COLOR := Color(0.15, 0.95, 0.3)
const AVAILABLE_GLOW_COLOR := Color(0.04, 0.7, 0.12)
## A Character committed to be played, waiting for its mana payment. Gold and
## narrow: not a prompt, and not a marker on a mana source.
const CAST_PENDING_BORDER_COLOR := Color(1.0, 0.82, 0.28)
const CAST_PENDING_GLOW_COLOR := Color(0.92, 0.61, 0.10)
## The material's own colours, captured when it is built so deselecting restores
## them. Safe because every card owns its own duplicate of the material.
var _border_color_base: Color = Color.WHITE
var _glow_color_base: Color = Color.WHITE
## ONE ring, SEVERAL meanings. Colour and visibility are derived from these flags together by
## _refresh_target_ring() rather than written to the material by each setter in turn: with
## several independent writers the last one to run decided the colour, and a setter that only
## recoloured left the ring dark (it has to be LIT as well — see set_highlight).
var _prompt_glow: bool = false
var _selected_highlight_on: bool = false
var _targeted_highlight_on: bool = false
var _available_highlight_on: bool = false
var _cast_pending_highlight_on: bool = false

## "The game is asking YOU to pick this" (blue) — the same meaning in the hand and on the field.
## "Mana has been spent on this card" — a glow in that mana's own colour, held until the card is played.
##
## The FIFTH meaning of one ring and deliberately the LOWEST priority: the other four are prompts telling the player to
## act, while this one only reports, so anything asking for attention outranks it.
var _energized_highlight_on: bool = false
var _energized_colour: Color = Color.WHITE

## WHAT THE RING IS SHOWING — the public way to ask, so callers and tests do not depend on the card's private flags.
## Reading a private flag through `card.get(...)` silently returns null once the flag is renamed, so a `not <that>`
## check would pass for the wrong reason. The ring's own flags live just below and stay private.
func ring_selected() -> bool:
	return _selected_highlight_on

func ring_targeted() -> bool:
	return _targeted_highlight_on

func ring_energized() -> bool:
	return _energized_highlight_on

func ring_cast_pending() -> bool:
	return _cast_pending_highlight_on

## The widths actually on the ring's live material, in metres — (border, glow). Read back from the material rather than
## from the constants, so a caller can tell "the green ring really is drawn at half width" from "the constants agree".
## Returns zero when there is no material yet (nothing has been lit).
func set_prompt_glow(enabled: bool) -> void:
	_prompt_glow = enabled
	_refresh_target_ring()

func set_selected_highlight(enabled: bool) -> void:
	if enabled == _selected_highlight_on:
		return
	_selected_highlight_on = enabled
	_refresh_target_ring()

## Mirror of set_selected_highlight() for the opponent's choice: red is "they picked this".
func set_targeted_highlight(enabled: bool) -> void:
	if enabled == _targeted_highlight_on:
		return
	_targeted_highlight_on = enabled
	_refresh_target_ring()

## "You could activate this card's effect right now" (see Field.can_activate_now).
func set_available_highlight(enabled: bool) -> void:
	if enabled == _available_highlight_on:
		return
	_available_highlight_on = enabled
	_refresh_target_ring()

## "This Character is the play and is waiting for mana." A thin gold aura,
## distinct from every prompt and from the elemental "mana was spent here"
## marker. The card is in its Character cast stance (or parked on the Stack for a
## Summon) while the payment modal is open, so the aura is what says it is already
## committed and must not also be used as a mana source.
func set_cast_pending_highlight(enabled: bool) -> void:
	if enabled == _cast_pending_highlight_on:
		return
	_cast_pending_highlight_on = enabled
	_refresh_target_ring()

## "You picked this card to pay a special ability's S cost" — pink, so it can never be confused with the orange
## targeting pick (the card you are choosing) or with the blue legal candidates.
##
## It is a payment rather than a prompt, which is why it outranks the other four meanings in _refresh_target_ring().
const S_COST_BORDER_COLOR := Color(1.0, 0.35, 0.75)
const S_COST_GLOW_COLOR := Color(0.95, 0.15, 0.6)
var _s_cost_highlight_on: bool = false

func set_s_cost_highlight(enabled: bool) -> void:
	if enabled == _s_cost_highlight_on:
		return
	_s_cost_highlight_on = enabled
	_refresh_target_ring()

func ring_s_cost() -> bool:
	return _s_cost_highlight_on

## "Mana has been spent on this card" — a glow in that element's colour, held until the card is played.
##
## This is the FIFTH meaning of one ring, and deliberately the LOWEST priority. The other four are prompts telling the
## player to ACT; this one only reports. Anything asking for attention therefore outranks it, which is exactly what the
## order of the checks in _refresh_target_ring() encodes — later wins.
##
## ONLY WHILE THE CARD IS STILL IN HAND, and that guard is load-bearing rather than tidiness. The glow is set when the
## mana lands, which for a CHARACTER is AFTER the card has been moved to the field: cast_card() calls
## field.play_card() (which runs enter_zone, clearing every ring) and the shatter that energizes runs after the play
## has landed. So the glow would be applied to a card whose rings had just been cleared, and nothing would clear it
## again — a Character never reaches the stack and it has already changed zone — leaving it lit on the board for the
## rest of the match. That is the reported bug.
##
## The rule this encodes is the one the glow is actually for: it marks a card you have PAID FOR BUT NOT YET PLAYED.
## Once the card has left your hand the play is happening and the glow has nothing left to say.
func set_energized_highlight(enabled: bool, colour: Color = Color.WHITE) -> void:
	if enabled and current_zone != Zone.HAND:
		return
	if enabled == _energized_highlight_on and (not enabled or colour.is_equal_approx(_energized_colour)):
		return
	_energized_highlight_on = enabled
	if enabled:
		_energized_colour = colour
	_refresh_target_ring()

## The material's stock widths, captured when the ring is built (see _build_target_border).
var _border_width_base: float = 0.025
var _glow_width_base: float = 0.07
## How wide the green availability ring is drawn, as a fraction of the others. It is a STANDING
## cue — it can sit on several cards for a whole turn — while blue/orange/red are momentary, so
## it is drawn thinner to stay subordinate to them.
const AVAILABLE_WIDTH_SCALE := 0.5
## The same argument again, taken further. An energized ring is a standing cue on the card that was
## paid into, and it is scenery next to the prompts rather than a signal, so it is thinner still.
const ENERGIZED_WIDTH_SCALE := 0.35
## ...and dimmer, because width alone left it reading like a prompt that never went away. Multiplied
## into the element colour rather than applied as a separate alpha, so the ring's own look is untouched.
const ENERGIZED_DIM := 0.65
## The committed-Character aura is deliberately thin: gold is the signal, not
## a wide ring competing with the prompt colours.
const CAST_PENDING_WIDTH_SCALE := 0.30

## Each element as a colour, for cues that should read as "THIS CARD" rather than "what paid for it".
##
## Keyed by the CJK character because that is what `element` holds — the same form MANA_ZERO and the
## payment code use. The values match ManaCrystal.CRYSTAL_TINT, so a card's glow and its crystals agree.
const ELEMENT_COLOURS := {
	"火": Color(0.86, 0.09, 0.17),   # fire
	"氷": Color(0.55, 0.87, 0.98),   # ice
	"風": Color(0.36, 0.85, 0.44),   # wind
	"土": Color(0.90, 0.74, 0.26),   # earth
	"雷": Color(0.72, 0.45, 1.00),   # lightning
	"水": Color(0.32, 0.58, 1.00),   # water
	"光": Color(1.00, 0.95, 0.78),   # light
	"闇": Color(0.58, 0.52, 0.86),   # dark
}

## This card's own element as a colour, dimmed for the energized ring. Falls back to `fallback` for an
## element not in the table, so an unknown or empty element still lights something rather than nothing.
func element_colour(fallback: Color) -> Color:
	var found: Color = ELEMENT_COLOURS.get(element, fallback)
	return found * ENERGIZED_DIM

## The single owner of the ring's appearance: LIT if any meaning is on, and coloured by
## priority — orange (my pick) over red (their pick) over green (available) over blue (merely
## legal), with energized below all of them. Lighting it is not optional: a ring that is
## coloured but not lit shows nothing on screen, which is how the red reveal once shipped invisible.
func _refresh_target_ring() -> void:
	var lit: bool = (_prompt_glow or _selected_highlight_on or _targeted_highlight_on
		or _available_highlight_on or _energized_highlight_on or _cast_pending_highlight_on
		or _s_cost_highlight_on)
	if target_border == null and not lit:
		# Nothing built and nothing wanted: do not build a ring just to switch it off.
		_highlight_on = false
		return
	if target_border == null:
		_build_target_border()
	if _border_material == null:
		return
	# Width before colour. Each state names its own scale and every other state restores the stock
	# width, so switching between states is exact rather than accumulating.
	var width_scale: float = 1.0
	if _available_highlight_on:
		width_scale = AVAILABLE_WIDTH_SCALE
	elif _cast_pending_highlight_on:
		width_scale = CAST_PENDING_WIDTH_SCALE
	elif _energized_highlight_on:
		width_scale = ENERGIZED_WIDTH_SCALE
	_border_material.set_shader_parameter("border_width", _border_width_base * width_scale)
	_border_material.set_shader_parameter("glow_width", _glow_width_base * width_scale)
	var color: Color = _border_color_base
	var glow: Color = _glow_color_base
	# LOWEST PRIORITY, so it is checked FIRST: everything below overwrites it. The colour is the CARD's
	# own element — the glow is about this card, not about which mana happened to pay for it.
	if _energized_highlight_on:
		color = element_colour(_energized_colour)
		glow = element_colour(_energized_colour)
	if _cast_pending_highlight_on:
		color = CAST_PENDING_BORDER_COLOR
		glow = CAST_PENDING_GLOW_COLOR
	if _available_highlight_on:
		color = AVAILABLE_BORDER_COLOR
		glow = AVAILABLE_GLOW_COLOR
	if _targeted_highlight_on:
		color = TARGETED_BORDER_COLOR
		glow = TARGETED_GLOW_COLOR
	if _selected_highlight_on:
		color = SELECTED_BORDER_COLOR
		glow = SELECTED_GLOW_COLOR
	# HIGHEST, so it is checked LAST: an S cost pick is a payment already made, while the four above are questions being
	# asked. Pink, so it is never confused with the orange targeting pick or the blue legal candidates.
	if _s_cost_highlight_on:
		color = S_COST_BORDER_COLOR
		glow = S_COST_GLOW_COLOR
	_border_material.set_shader_parameter("border_color", color)
	_border_material.set_shader_parameter("glow_color", glow)
	set_highlight(lit)

## Show/hide the selectable/targetable glow. Fades so the cue does not pop, and
## is cheap to call repeatedly: Hand.refresh_highlights() runs on every layout,
## so an unchanged request must not restart the tween.
func set_highlight(enabled: bool) -> void:
	if target_border == null:
		_build_target_border()
	if target_border == null:
		return
	if enabled == _highlight_on:
		return
	_highlight_on = enabled
	if not is_inside_tree():
		_border_material.set_shader_parameter("intensity", 1.0 if enabled else 0.0)
		target_border.visible = enabled
		return
	if _border_tween != null and _border_tween.is_valid():
		_border_tween.kill()
	_border_tween = create_tween()
	if enabled:
		target_border.visible = true
	_border_tween.tween_method(_set_border_intensity, _border_intensity(), 1.0 if enabled else 0.0, 0.12)
	if not enabled:
		_border_tween.tween_callback(func(): target_border.visible = false)

func _border_intensity() -> float:
	return float(_border_material.get_shader_parameter("intensity"))

func _set_border_intensity(value: float) -> void:
	_border_material.set_shader_parameter("intensity", value)

## Built in code rather than authored in card.tscn so the quad can be sized from
## the card mesh's own AABB: the ring then lands on whatever silhouette the art
## has, and nothing in the scene tree has to be kept in sync by hand.
##
## The quad must COVER the whole glow, and the quad's edge is what crops it if it
## does not: the ring is drawn outside the card (half-extent = card_size/2 +
## margin). So the margin is DERIVED here from the material's own ring/spill widths
## instead of being tuned by hand — raise `border_width` or `glow_width` and the
## quad grows with it. The floors only exist so a failed parameter lookup (which
## returns null, i.e. 0.0) cannot collapse the quad onto the card and crop the ring.
const BORDER_MARGIN_MIN := 0.05

## Reported once per run so the numbers the shader is actually using are visible in
## the output — the quickest way to tell whether a .tres tweak is reaching it.
static var _border_look_reported: bool = false

func _report_target_border_look(size: Vector2, margin: float) -> void:
	if _border_look_reported:
		return
	_border_look_reported = true
	LOG.info("TargetBorder", "card=%s quad=%s border_width=%.3f border_color=%s glow_width=%.3f glow_color=%s" % [
		size,
		size + Vector2.ONE * margin * 2.0,
		float(_border_material.get_shader_parameter("border_width")),
		str(_border_material.get_shader_parameter("border_color")),
		float(_border_material.get_shader_parameter("glow_width")),
		str(_border_material.get_shader_parameter("glow_color")),
	])

func _build_target_border() -> void:
	if target_border != null:
		return
	var size: Vector2 = _card_face_size()
	# The look lives in target_border_material.tres so it can be tuned in the
	# Inspector; duplicated so every card owns its own fade.
	_border_material = TARGET_BORDER_MATERIAL.duplicate()
	_border_material.set_shader_parameter("card_size", size)
	_border_material.set_shader_parameter("intensity", 0.0)
	# Remember the stock colours so set_selected_highlight() can put them back.
	var border_color: Variant = _border_material.get_shader_parameter("border_color")
	if border_color is Color:
		_border_color_base = border_color
	var glow_color: Variant = _border_material.get_shader_parameter("glow_color")
	if glow_color is Color:
		_glow_color_base = glow_color
	# ...and the stock WIDTHS, so a state can be drawn thinner (the green availability ring is
	# half width) without losing the look the material was tuned to.
	_border_width_base = maxf(float(_border_material.get_shader_parameter("border_width")), 0.005)
	_glow_width_base = maxf(float(_border_material.get_shader_parameter("glow_width")), 0.0)
	# Size the quad from the ring + spill, and write the result back so the shader
	# and the geometry can never disagree about where the glow ends.
	var border_width: float = _border_width_base
	var glow_width: float = _glow_width_base
	# 3x the spill width is roughly where its exponential has decayed to ~5%.
	var margin: float = maxf(border_width + glow_width * 3.0 + 0.01, BORDER_MARGIN_MIN)
	_border_material.set_shader_parameter("margin", margin)
	_report_target_border_look(size, margin)
	var plane := PlaneMesh.new()
	# PlaneMesh lies in the XZ plane with normal +Y — the same plane the card mesh
	# uses (card.tres AABB), so it needs no rotation.
	plane.size = size + Vector2.ONE * margin * 2.0
	target_border = MeshInstance3D.new()
	target_border.name = "TargetBorder"
	target_border.mesh = plane
	target_border.material_override = _border_material
	# A hair above the face (the card quad sits at y ~ 0) so they never z-fight;
	# the shader draws nothing inside the silhouette either way.
	target_border.position = Vector3(0, 0.002, 0)
	target_border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target_border.visible = false
	# Parented to the visible mesh, NOT to the Card: the hand's hover animation
	# moves and scales HandMesh without touching the Card, so a sibling border
	# would be left behind. As a child it follows the lift and scales with the
	# card, which is what keeps the ring hugging the edge.
	var border_parent: Node3D = (hand_mesh as Node3D) if hand_mesh != null else (self as Node3D)
	border_parent.add_child(target_border)

## Card face size in metres. The mesh is a flat quad in XZ (0.429 x 0.6), so the
## AABB's x is the width and its z the height.
func _card_face_size() -> Vector2:
	if hand_mesh != null and hand_mesh.mesh != null:
		var aabb: AABB = hand_mesh.mesh.get_aabb()
		if aabb.size.x > 0.0 and aabb.size.z > 0.0:
			return Vector2(aabb.size.x, aabb.size.z)
	return Vector2(0.429, 0.6)

## Target matching lives in the shared TARGET BLOCK evaluator — see scripts/card_target.gd.

func is_type(ntype:String) -> bool:
	return self.type == ntype

## "Character" is any card that lives on the field as a unit: Forward, Backup or Monster. Card text says it
## constantly ("choose 1 Character"), so it gets a predicate rather than repeating the list in every criteria block.
##
## IT TAKES AN ARGUMENT even though it needs none: `matches_criteria` calls every predicate as `callv(name, [value])`,
## so a zero-argument predicate is an invalid call and every candidate silently becomes illegal.
func is_character(_want = true) -> bool:
	return type in ["Forward", "Backup", "Monster"]

## One criterion, several accepted types: {"is_type_any": ["Forward", "Monster"]} — because the criteria vocabulary is
## AND-only and card text often says "Forward or Monster".
func is_type_any(types) -> bool:
	for t in types:
		if is_type(str(t)):
			return true
	return false

func is_cost_lower_than(value: int) -> bool:
	return cost < value

## "a Forward of cost 5 or more" (Ifrit 1-061R).
func is_cost_at_least(value: int) -> bool:
	return int(cost) >= int(value)

## "a Backup of cost 3 or less" (Archer 1-088C).
func is_cost_at_most(value: int) -> bool:
	return int(cost) <= int(value)

## "Bartz has all the jobs" (81). Every job check succeeds for him, so a future "choose 1 [Job (X)]" finds him.
## A normal card matches by SUBSTRING, the same way the deck editor's job filter reads it.
func is_job(value: String) -> bool:
	var effect_obj = effect() if abilities_enabled() else null
	if effect_obj != null and effect_obj.has_all_jobs():
		return true
	var data: Dictionary = CardDatabase.card_database[id - 1]
	return str(value).to_lower() in str(data.get("job_en", "")).to_lower()

## "[Category (VII)]" (Cloud 1-009C). Checks the card's categories from the database; a card can have several.
func is_category(value: String) -> bool:
	var data: Dictionary = CardDatabase.card_database[id - 1]
	for key in ["category_1", "category_2", "category_3"]:
		if str(data.get(key, "")) == value:
			return true
	return false

func is_named(value: String) -> bool:
	# Card-name condition (e.g. "if you control a card named Aerith").
	return card_name == value

const ELEMENT_NAMES = {
	"Fire": "火",
	"Ice": "氷",
	"Wind": "風",
	"Earth": "土",
	"Lightning": "雷",
	"Water": "水",
	"Light": "光",
	"Dark": "闇",
}

## The stateless code effect for this card id, if one is registered. Falls back to the JSON path when null.
func effect():
	if _card_effect == null:
		_card_effect = EFFECT_REGISTRY.for_card_id(id)
	return _card_effect


func effect_handles_event(event) -> bool:
	var effect_obj = effect()
	if effect_obj == null:
		return false
	# Accept a legacy string at the boundary while call sites migrate to EVENTS.Event.
	return effect_obj.handles_event(EVENTS.normalize(event))


## Human-readable event name for logs, stack snapshots and tests.
func effect_auras() -> Array:
	var effect_obj = effect()
	var out: Array = []
	if effect_obj != null and effect_obj.has_method("auras"):
		out.append_array(effect_obj.auras())
	if not extra_auras.is_empty():
		out.append_array(extra_auras)
	return out


## Build the explicit world for one effect invocation. A source card normally sits under Field; a stack copy sits
## under Stack. Either way the Game is the grandparent and EffectContext resolves Field from it.
func make_effect_context(event = "static", data: Dictionary = {}, effect_card: Card = null, targets: Array = []):
	# USE THE STACK COPY TO FIND THE GAME. A self-sacrificing ability's source has already left the field by the time
	# the ability resolves, so walking up from this card reaches the Break Zone's PlayerSide, not the Game. The effect
	# copy is on the Stack, whose parent IS the Game, and that is the stable path for every resolving ability.
	var anchor: Node = effect_card if effect_card != null and is_instance_valid(effect_card) and effect_card.is_inside_tree() else self
	# WALK UP TO THE GAME, identified by the seam methods it owns: a card may have moved to hand/deck before
	# resolution, so a fixed card -> owner -> Game path is not reliable.
	var game: Node = null
	var node: Node = anchor.get_parent()
	while node != null:
		if node.has_method("agent_for") and node.has_method("hand_for"):
			game = node
			break
		node = node.get_parent()
	return EFFECT_CONTEXT.new(game, self, event, data, effect_card, targets)


## EVERY Element this card currently has, in the order it should be displayed. The printed `element` remains the
## immutable base; a code effect may add or replace it. Re-entrancy returns the base element so two Kimahris cannot
## recurse forever while each asks the other what Elements it has.
func current_elements() -> Array[String]:
	if _elements_calculating:
		return [element] if element != "" else []
	# A temporary "becomes this Element" status replaces the whole set (Mime 173). It is checked before the printed
	# element, so an override really does replace rather than add.
	if status_effects.has("element_override"):
		var override = status_effects["element_override"]
		if override is Dictionary and str(override.get("element", "")) != "":
			return [str(override["element"])]
	_elements_calculating = true
	var out: Array[String] = []
	if element != "":
		out.append(element)
	# "Loses all abilities" also loses a continuous element grant.
	if abilities_enabled():
		var effect_obj = effect()
		if effect_obj != null and effect_obj.has_method("current_elements"):
			var extra = effect_obj.current_elements(make_effect_context(), self)
			if extra is Array:
				for e in extra:
					if e != null and str(e) != "" and not out.has(str(e)):
						out.append(str(e))
	_elements_calculating = false
	return out


func is_element(value: String) -> bool:
	# Accepts either the English element name ("Fire") or the game's single-character element code ("火").
	var wanted: String = ELEMENT_NAMES.get(value, value)
	return wanted in current_elements()


## Elements this card can produce for CP. Kept separate from `current_elements` because payment may eventually ask
## the player to choose one when a card has several; for now it is the same query.
func mana_elements() -> Array[String]:
	# A Backup that produces "any Element" offers every colour; a card with several printed/current elements offers
	# exactly those. The payment UI asks the player to choose when this has more than one entry.
	if produces_any_element():
		return ELEMENTS.CJK.duplicate()
	return current_elements()

func is_light_or_dark() -> bool:
	return is_element("Light") or is_element("Dark")

## "light" / "dark" / "" — the two elements with the rule that you may normally control only one such card.
func light_dark_kind() -> String:
	if is_element("Light"):
		return "light"
	if is_element("Dark"):
		return "dark"
	return ""

## A Backup can print "produces CP of any Element" (Cosmos/Chaos). The card only behaves that way while it is on
## the field; `mana_element()` is what the payment UI asks instead of reading `element` directly.
func produces_any_element() -> bool:
	if not is_on_field():
		return false
	var effect_obj = effect() if abilities_enabled() else null
	return (effect_obj != null and effect_obj.produces_any_element()) \
		or status_effects.has("produces_any_element")


## Static flags read through the effect object, so callers never inspect static rule dictionaries.
func disables_ex_burst() -> bool:
	var effect_obj = effect() if abilities_enabled() else null
	return effect_obj != null and effect_obj.disables_ex_burst()


func exiles_break_zone() -> bool:
	var effect_obj = effect() if abilities_enabled() else null
	return effect_obj != null and effect_obj.exiles_break_zone()


func light_dark_exemption() -> String:
	var effect_obj = effect() if abilities_enabled() else null
	return effect_obj.light_dark_exemption() if effect_obj != null else ""


func grants_party_brave() -> bool:
	var effect_obj = effect() if abilities_enabled() else null
	return effect_obj != null and effect_obj.grants_party_brave()

func mana_element() -> String:
	return "any" if produces_any_element() else element


## The colour this source produces for payment. Code effects may ask the player (the any-colour and multi-element
## cards); everything else falls back to the printed/current colour. The context is optional only because plain
## cards never need it.
func generate_mana(ctx: EFFECT_CONTEXT = null) -> String:
	var effect_obj = effect() if abilities_enabled() else null
	if effect_obj != null and effect_obj.has_method("generate_mana"):
		return str(await effect_obj.generate_mana(ctx))
	return mana_element()

const CARD_TARGET := preload("res://scripts/card_target.gd")

## Is this card within `criteria`? Delegated to the shared TARGET BLOCK evaluator, which also understands the `exclude`
## rule — "other than Aerith" — and skips session keys like `count`. See scripts/card_target.gd for the three kinds of
## key. The signature is unchanged, so existing callers and data keep working exactly as they did.
##
## `source` is optional and only matters for the relative keys an exclude block can use ("other than THIS card", "one of
## YOURS"). A caller that does not pass one simply cannot use those keys; nothing else changes.
func matches_criteria(criteria: Dictionary, source: Card = null) -> bool:
	return CARD_TARGET.matches(self, criteria, source)

func get_effect_kind() -> String:
	# Targeting-source kind for protection checks: "Summon" or "Ability".
	# Explicit effect_kind wins; otherwise derive from the card itself.
	if effect_kind != "":
		return effect_kind
	if type == SUMMON:
		return "Summon"
	if is_effect_card():
		return "Ability"
	return ""

func can_be_chosen_by(source: Card, source_kind: String = "") -> bool:
	# GRANTED PROTECTION FIRST, and deliberately unconditional: a card that has been GIVEN this status cannot be chosen by
	# ANY source, its own controller's included. Aerith's Planet Protector protects your Forwards from your own Summons and
	# abilities as well — that is what the card says and what was asked for. It expires with the status, at the end of the
	# turn it was granted (Card.turn_end).
	#
	# Checked before the `source == null` exit below, because a caller that passes no source must not thereby bypass it.
	if status_effects.has("cannot_be_chosen"):
		return false
	if source == null:
		return true
	var effect_obj = effect() if abilities_enabled() else null
	if effect_obj != null:
		var ctx = TARGET_CONTEXT.new(self, source, source_kind, self)
		if effect_obj.prevents_being_chosen(ctx):
			return false
	return true

## "Summons or abilities of your opponent must choose Cecil if possible." The FIELD uses this to shrink the viable
## set to the mandatory cards when there is at least one legal one.
func must_be_chosen_by(source: Card, source_kind: String = "") -> bool:
	if source == null:
		return false
	var effect_obj = effect() if abilities_enabled() else null
	if effect_obj == null:
		return false
	return effect_obj.must_be_chosen(TARGET_CONTEXT.new(self, source, source_kind, self))

## Gilgamesh 207: "cannot be returned to its owner's hand by opponent's Summons or abilities."
func can_be_returned_to_hand_by(source: Card, source_kind: String = "") -> bool:
	if source == null:
		return true
	var effect_obj = effect() if abilities_enabled() else null
	if effect_obj == null:
		return true
	return not effect_obj.prevents_return_to_hand(TARGET_CONTEXT.new(self, source, source_kind, self))

## Criteria predicates. A criteria key becomes a Card method called with the block's value, so
## {"is_tapped": false} and {"is_tapped": true} must both mean what they say.
func is_tapped(want: bool = true) -> bool:
	return self.tapped == want

## "a damaged Forward" — any damage at all, which is what the card text means (not "below its power").
func is_damaged(want: bool = true) -> bool:
	return (accumulated_damage > 0) == want

## "a blocking Forward" / "an attacking Forward". Both keys are already maintained by
## set_attacker_status() and set_blocker_status(), and both expire at turn_end like any other status.
func is_attacking(want: bool = true) -> bool:
	return status_effects.has("attacking") == want

func is_blocking(want: bool = true) -> bool:
	return status_effects.has("blocking") == want

func set_attacker_status(active: bool) -> void:
	if active:
		status_effects['attacking'] = 1
		position.z += 0.05
	else:
		status_effects.erase('attacking')
		position.z -= 0.05

## Transient "selected as this combat's blocker" marker. Mirrors
## set_attacker_status() but keeps its own status key, so being a blocker never
## masquerades as being an attacker.
func set_blocker_status(active: bool) -> void:
	if active:
		status_effects['blocking'] = 1
		position.z += 0.05
	else:
		status_effects.erase('blocking')
		position.z -= 0.05
	
func check_controller(args) -> bool:
	if args is Array:
		return self.controller == args[0]
	return self.controller == args

func get_global_center():
	return global_position + Vector3(0.2,0.3,0)

## True centre of the card's FACE in world space. The card mesh is centred on its own
## origin, so this is simply the position. (get_global_center() above adds a fixed
## (0.2, 0.3, 0) offset and is NOT the centre; it is left alone because other callers
## depend on its behaviour, but anything that must land exactly on the middle of the
## card — the targeting arc's destination — uses this.)
func get_global_face_centre() -> Vector3:
	return global_position

## Mid-point of the edge the player sees as the card's TOP, in world space. The
## targeting arc leaves from here rather than from the middle of the card.
func get_global_top_centre() -> Vector3:
	var half_height: float = _card_face_size().y * 0.5 * global_transform.basis.z.length()
	var axis: Vector3 = global_transform.basis.z.normalized()
	var edge_a: Vector3 = global_position + axis * half_height
	var edge_b: Vector3 = global_position - axis * half_height
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return edge_a
	# Viewport y grows downwards, so the smaller projection is the edge that reads as
	# the top. Testing the two candidate edges keeps this right whatever the card's own
	# rotation or fan tilt happens to be.
	return edge_a if cam.unproject_position(edge_a).y <= cam.unproject_position(edge_b).y else edge_b

func is_effect_card() -> bool:
	# Real cards cast from hand have an empty key_word_effect. Only stack
	# copies (triggered abilities, skill proxies) are effect cards.
	return key_word_effect != ""
	
## The card reacts to being hit by a payment orb: a short flash of the orb's colour across its face, and a punch.
##
## BOTH TOGETHER is what reads as absorption rather than decoration. Either one alone reads as an effect happening near
## the card; light arriving AND the card physically receiving it reads as the card taking something in.
##
## The flash is its own quad rather than a tint on the card's own material. The art material carries the prompt-ring
## state — blue, orange, red and green all live in one set of shader parameters — and this must not touch any of it, so
## the flash borrows the orb's halo shader instead and throws it away afterwards.
##
## The punch restores whatever scale the card had when it was hit rather than a hard-coded one, so it cannot fight
## enter_zone(), which owns the per-zone scale. A zone change mid-tween simply overwrites it.
## THE REACTION ITSELF LIVES IN scripts/card_absorb.gd — the flash, the shockwave and the punch, with their quads and
## tweens. What stays here is the part that is the CARD's business: the tunable knobs and the glow.
##
## Preloaded by PATH, not referenced by a global class name: a new `class_name` is not in Godot's class cache until the
## editor rescans, and every headless run of this project has been bitten by that.
const CARD_ABSORB := preload("res://scripts/card_absorb.gd")

## Seconds the whole reaction lasts, how much the card swells at its peak, and how far the ring travels (as a multiple
## of the card's own width). @exported HERE so they stay tunable in the Inspector — that is how the punch was tuned, and
## moving them into the strategy would have quietly taken that away.
@export var absorb_seconds: float = 0.25
@export var absorb_punch: float = 1.15

## Created on first use. It owns the two quads and their tweens; this card owns the knobs it is handed.
var _absorb = null

## `at` is the impact point in WORLD space — where the orb was when it vanished. The shockwave is centred there, after
## being projected onto the card's plane; a zero vector means none was supplied and the ring falls back to the middle.
func absorb_power(colour: Color, at: Vector3 = Vector3.ZERO) -> void:
	if not is_inside_tree():
		return
	if _absorb == null:
		_absorb = CARD_ABSORB.new(self)
	_absorb.seconds = absorb_seconds
	_absorb.punch = absorb_punch
	# The face size is measured HERE and handed over: reading the mesh is the card's business, not the reaction's.
	_absorb.play(colour, at, _card_face_size())
	# THE GLOW HOLDS, unlike the flash and the ring: it stays until the card is played, which is what makes it a STATE
	# rather than an event. It is drawn in the mana's own colour and is the ring's lowest-priority meaning, so any
	# prompt outranks it. Stack clears it when the card reaches the top of the stack; a zone change clears it for a
	# Character, which never enters the stack at all. It is set from here rather than inside CardAbsorb because it is the
	# RING, not a reaction — the two only happen to fire together.
	set_energized_highlight(true, colour)
