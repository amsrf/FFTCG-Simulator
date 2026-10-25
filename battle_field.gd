extends Node3D
class_name Field


const CARD_CHARGE = 1
const RULES := preload("res://scripts/rules.gd")
## Continuous-effect queries. The BOARD owns its rulebook, not Game: created here in _ready, so the forwarders below
## work as soon as the board exists and never depend on the parent's initialisation order.
var rules = null

func _ready() -> void:
	rules = RULES.new()
	rules.bind(self)

var front_cards: Array[Card] = []
var back_cards: Array[Card] = []
var opponent_front_cards: Array[Card] = []
var opponent_back_cards: Array[Card] = []
var target_card: Card = null
var source_card: Card = null
var attacker_card: Card = null
## The blocker declared for the current combat. Persisted on the Field because the
## instruction chain ends before DAMAGE_RESOLUTION reads it, so a transient copy
## on Game would already be gone by then.
var blocker_card: Card = null
var arrow: BallisticArrow
## SEPARATE arrows for the combat's block links. The targeting arrow above belongs to a targeting session and follows
## the mouse; sharing instances would let either one re-aim or hide the other. A block against a PARTY needs one arc
## per member, so this is a list rather than a single arrow.
var block_arrows: Array = []
## If false (e.g. ETB), targeting cannot be cancelled and stack effect is mandatory.
var targeting_allow_cancel: bool = false
## MULTI-TARGET SESSIONS. `choose_target` may carry a "count" (default 1). At 1 nothing below changes: one pick, one arc,
## straight to Confirm. Above 1 the session keeps a list — each pick leaves its own arc locked on the card, a fresh aiming
## arc appears for the next, picked cards come out of the legal set, and Confirm only appears once the last pick is made.
##
## `target_card` stays the LAST pick, so every existing consumer (instruction resolution, the agents, the stack) is
## untouched; `targeting_picked` is the whole list, in order.
var targeting_count: int = 1
var targeting_picked: Array[Card] = []
var targeting_arrows: Array = []
var targeting_criteria_now: Variant = {}
var targeting_source_kind: String = ""
## Where this session's candidates come from: "field" (default) or "stack". Set from the effect's
## `"choose_target": {"in": "stack"}` — Summoner 53 picks a Summon that has not resolved yet.
var targeting_domain: String = "field"
## SEQUENTIAL STAGES. "Choose 1 Forward and 1 Backup" is one criteria block per pick stage:
## `"choose_target": [ {...Forward...}, {...Backup...} ]`. A single block (the normal case) is a one-element list,
## and `count` keeps its old meaning WITHIN a stage (Aerith's "up to 3 Backups").
var targeting_blocks: Array = []
var targeting_block_index: int = 0
var targeting_block_start: int = 0
## "When Kuja is chosen by an opponent's Summon or ability" fires ONCE per targeting session, on CONFIRM — not on
## every ring-click, and not when a pick is replaced before confirming. Reset by request_target.
var _chosen_notified: bool = false
signal selected_cards_for_mana_has_changed(amount:int, element:String)
signal add_card_effect_to_stack(card_id:int, keyword:String, source:Card)
signal request_target_confirmation(target_card: Card, allow_cancel: bool)
signal attacker_changed
signal blocker_changed
signal card_activated_ability(cost:Dictionary)
## Read-through to the match's phase (owned by `Game`); Field keeps no copy.
var phase: GlobalVariables.Phase:
	get:
		return get_parent().phase
@export var selected_cards_for_mana_conversion: Array[Card] = []
@onready var ballistic_arrow_scene = preload("res://ballistic_arrow.tscn")
@onready var assistant: Assistant = get_parent().get_node("Assistant")
@onready var stack: Stack = get_parent().get_node("Stack") as Stack
@onready var hand: Hand = get_parent().get_node("Player/Hand") as Hand

# ------------------------------------------------------------------
# Field card preview (hover)
# ------------------------------------------------------------------
## A field card is drawn small — that is the whole point of a board — so its rules text cannot be read
## there. Hovering one shows the full scan at a readable size, the same idea (and the same placement
## rule) as the deck editor's and the search window's hover previews, so hovering reads the same way
## everywhere in the game.
##
## The preview is deliberately screen-space: a CanvasLayer over the board, not a mesh in it. It must
## not be pickable, must not cast anything, and must never take part in targeting — it is a reading
## aid, not a game object.
##
## It is built on first hover, so a match where nobody hovers a field card never pays for it.

## Height of the preview as a fraction of the viewport. 0.38 is a ~410 px card at 1080p: comfortable to
## read without covering the board. The first value tried was 0.62, which is a ~670 px card and far too
## much — it read as a takeover rather than a preview. Tune in the Inspector while the game runs.
@export var preview_height_fraction: float = 0.38
## Gap between the hovered card and the preview, in screen pixels.
@export var preview_gap: float = 16.0
@export var preview_grow_seconds: float = 0.12
## Card scans are 2:3 — the preview's width follows from its height through this.
const PREVIEW_ASPECT: float = 0.667
const CARD_VIEW := preload("res://scripts/card_view.gd")

var _preview_layer: CanvasLayer = null
var _preview: TextureRect = null
var _preview_tween: Tween = null
## The card the preview is currently showing, so a hide can be ignored when it belongs to a different
## card than the one being left (a gap between two cards fires enter/exit in a fiddly order).
var _preview_card: Card = null


func _preview_size() -> Vector2:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var h: float = view.y * preview_height_fraction
	return Vector2(h * PREVIEW_ASPECT, h)


func _ensure_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		return
	_preview_layer = CanvasLayer.new()
	# Above the board but below the DeckSearch window (10) and the buttons' own canvas, so a modal
	# still covers it rather than being covered by it.
	_preview_layer.layer = 5
	add_child(_preview_layer)
	_preview = TextureRect.new()
	# ROUNDED CORNERS AND THE THIN BLACK BOTTOM LINE, from the same shader the deck editor's and the search
	# window's previews use. Reusing it rather than redrawing the effect here means a hovered card looks the
	# same everywhere in the game, and the corner radius stays a single number to change.
	#
	# THE LINE IS SET IN PIXELS. The shader's default edge_depth is 0.004 in UV — a FRACTION of the image — which
	# on a preview this size comes out at about 1.6 px. It was drawing all along and was simply too fine to
	# notice, which is why it looked absent. A pixel width over the preview's height gives the UV figure the
	# shader wants, and keeps the number in the units a person actually thinks in.
	const PREVIEW_LINE_PIXELS: float = 3.0
	var preview_material: ShaderMaterial = CARD_VIEW.round_material()
	var preview_size: Vector2 = _preview_size()
	if preview_size.y > 0.0:
		preview_material.set_shader_parameter("edge_depth", PREVIEW_LINE_PIXELS / preview_size.y)
	_preview.material = preview_material
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	# Never takes the mouse: the preview must not steal hover from the card that opened it.
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	_preview_layer.add_child(_preview)


## Show the full scan of `card`. Placed to the RIGHT of it, or to the LEFT when there is no room,
## then clamped into the viewport — the same rule the deck editor uses.
func show_card_preview(card: Card) -> void:
	if card == null or not is_instance_valid(card):
		return
	_ensure_preview()
	if _preview == null:
		return
	# CardView owns "where does this card's art live, and is there any" — one definition, checked in
	# one place, rather than a second copy of the path convention here.
	var path: String = CARD_VIEW.art_path(card.id)
	var tex: Texture2D = null
	if not path.is_empty():
		tex = load(path) as Texture2D
	if tex == null:
		hide_card_preview()
		return

	_preview_card = card
	_preview.texture = tex
	var size: Vector2 = _preview_size()
	_preview.size = size
	_preview.pivot_offset = size * 0.5

	var view: Vector2 = get_viewport().get_visible_rect().size
	# PLACE IT OUTSIDE THE CARD, NOT BESIDE ITS CENTRE. Offsetting from the centre put the preview's left edge
	# ~16 px right of the middle of the card, so the thing meant to help you read the card covered its right half.
	# The edges come from projecting the card's four face corners, which is what makes this survive the field's
	# rotation and the card's own tilt instead of assuming an upright card of a known size.
	var cam: Camera3D = get_viewport().get_camera_3d()
	var rect: Rect2 = Rect2()
	if cam != null:
		# A card face is 0.429 wide by 0.6 tall in its own space: x is the width axis, z the height. The
		# transform scale is not 1 (a zone sets it), so it is read rather than assumed.
		var s: Vector3 = card.global_transform.basis.get_scale()
		var across: Vector3 = card.global_transform.basis.x.normalized() * (0.429 * 0.5 * s.x)
		var along: Vector3 = card.global_transform.basis.z.normalized() * (0.6 * 0.5 * s.z)
		var corners: Array[Vector3] = [
			card.global_position + across + along, card.global_position + across - along,
			card.global_position - across + along, card.global_position - across - along]
		var mn: Vector2 = Vector2(INF, INF)
		var mx: Vector2 = Vector2(-INF, -INF)
		for p in corners:
			var sp: Vector2 = cam.unproject_position(p)
			mn = mn.min(sp)
			mx = mx.max(sp)
		rect = Rect2(mn, mx - mn)
	var anchor: Vector2 = rect.position + rect.size * 0.5
	var edge_right: float = rect.position.x + rect.size.x
	var edge_left: float = rect.position.x
	if rect.size.x <= 0.0:
		# No camera, or a degenerate projection: fall back to the middle of the screen, still preferring the right.
		anchor = view * 0.5
		edge_right = anchor.x
		edge_left = anchor.x
	var x: float = edge_right + preview_gap
	if x + size.x > view.x - 8.0:
		# No room to the right of the card, so put it to the LEFT of the card instead.
		x = edge_left - preview_gap - size.x
	x = clampf(x, 8.0, maxf(8.0, view.x - size.x - 8.0))
	var y: float = anchor.y - size.y * 0.5
	y = clampf(y, 8.0, maxf(8.0, view.y - size.y - 8.0))
	_preview.position = Vector2(x, y)
	_preview.visible = true

	# Grow in from small rather than popping, exactly like the deck editor's preview.
	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
	_preview.scale = Vector2.ONE * 0.1
	_preview_tween = create_tween()
	_preview_tween.tween_property(_preview, "scale", Vector2.ONE, preview_grow_seconds)


func hide_card_preview() -> void:
	_preview_card = null
	if _preview != null and is_instance_valid(_preview):
		_preview.visible = false


## Which card the preview is showing, or null. Exposed for tests and for anything that needs to know
## whether the preview is up without reading a private field.
func preview_card() -> Card:
	return _preview_card


func preview_visible() -> bool:
	return _preview != null and is_instance_valid(_preview) and _preview.visible

class AuraValue:
	var method: String
	var targets: Dictionary  # Changed from Array[String] to Dictionary
	var value: int
	## For method == "grant_status": the keyword/status this aura grants ("first_strike", "haste", ...).
	var status: String
	## THE CARD THAT GRANTED IT, held so auras can be found by their source instead of by a dictionary key equal to the
	## source's instance id — which is what limited a card to one aura: a second entry under the same key overwrote the
	## first before anything had applied it, and the teardown only ever undid the survivor.
	var source: Card = null
	## The cards this aura has ALREADY been applied to. Without it the same card can be reached twice — a card arriving
	## runs add_all_auras_to_card(), and an aura arriving runs activate_aura_in_field() over everything — and a
	## power_change applied twice is permanent, silent, and only visible as a wrong number much later.
	var granted: Dictionary = {}

	func _init(p_method: String, p_targets: Dictionary, p_value: int = 0, p_status: String = ""):
		method = p_method
		targets = p_targets
		value = p_value
		status = p_status


## Every aura, each under its OWN id. This was a Dictionary keyed by the source card's instance id, so a card that granted
## two things kept only the last one. No card in the data has two auras today — which is exactly why it was worth fixing
## before one does, since the failure would be a silently missing bonus rather than an error.
var _auras: Dictionary[int, AuraValue] = {}
var _next_aura_id: int = 1

func add_aura(aura: Dictionary, source: Card) -> AuraValue:
	var aura_value := AuraValue.new(str(aura.get('method', '')), aura.get('targets', {}),
		int(aura.get('value', 0)), str(aura.get('status', '')))
	aura_value.source = source
	_auras[_next_aura_id] = aura_value
	_next_aura_id += 1
	return aura_value
	
func activate_aura_in_field(aura:AuraValue):
	var all_cards: Array[Card] = get_all_cards()
	for card:Card in all_cards:
		add_aura_to_card(aura,card)

## APPLIED AT MOST ONCE PER CARD. `granted` is the guard; it is also the exact record the teardown needs, so taking the
## bonus back does not have to re-derive which cards it went to from the target test.
##
## Routed through the SAME evaluator as choose_target (scripts/card_target.gd), so an aura and an effect mean the same
## thing by "type: Forward, controller: player" — and an aura can now say `exclude` or `is_named` too, which the old
## does_card_match_target() could not express at all.
const CARD_TARGET := preload("res://scripts/card_target.gd")

func add_aura_to_card(aura: AuraValue, card: Card):
	# `aura.source` is the card GRANTING the aura, so "your Fire Forwards" is read from its controller — not from a
	# fixed seat. An AI-owned aura would otherwise buff the human's board.
	if not CARD_TARGET.matches(card, aura.targets, aura.source):
		return
	if aura.granted.has(card):
		return
	aura.granted[card] = true
	if aura.method == 'power_change':
		# -1 = permanent modifier (does not expire at end of turn).
		card.power_change(aura.value, -1)
	elif aura.method == 'grant_status' and not aura.status.is_empty():
		# Keywords from a continuous effect ("the Standard Unit Forwards gain First Strike"). Counted, so two
		# sources can grant the same keyword and one leaving does not revoke the other's.
		card.grant_status(aura.status)
				
func add_all_auras_to_card(card:Card):
	for aura in _auras.values():
		add_aura_to_card(aura,card)		

func add_card_to_mana_conversion(card:Card):
	if  not selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.push_back(card)
	# Owns the marker, so an agent paying a cost gets the same feedback as a click.
	card.show_mana_crystal()
	selected_cards_for_mana_has_changed.emit(1,card.element)
	
func remove_card_from_mana_conversion(card:Card):
	if selected_cards_for_mana_conversion.has(card):
		selected_cards_for_mana_conversion.erase(card)
	card.clear_mana_crystal()
	selected_cards_for_mana_has_changed.emit(-1,card.element)


## Apply every static `on_character_enter` rule currently on the board to a card that just entered. This is a BOARD
## QUERY, not a registered listener: the rule lives on its source card and is read while that source is on the field,
## so a source that leaves stops contributing with no teardown at all.
func _apply_entry_rules(entering: Card) -> void:
	if entering == null or not is_instance_valid(entering):
		return
	for source in get_all_cards():
		if source == null or not is_instance_valid(source) or not source.is_on_field():
			continue
		var rules = source.card_effects.get("on_character_enter", [])
		if rules is Dictionary:
			rules = [rules]
		if not (rules is Array):
			continue
		for rule in rules:
			if not (rule is Dictionary):
				continue
			if not CARD_TARGET.matches(entering, rule.get("targets", {}), source):
				continue
			var action: String = str(rule.get("action", ""))
			match action:
				"dull", "tap":
					entering.tap()
				_:
					push_warning("[EntryRule] %s: unknown action '%s'" % [source.card_name, action])


func play_card(card, is_opponent: bool = false, animate = true, record: bool = true) -> void:
	# UNIQUE NAMES. A player may not control two Characters with the same name. Checked BEFORE the reparent, so the
	# duplicate never touches the field: it did not enter, so no enter-the-field trigger and no entry animation run.
	# The card already on the field is kept; the new copy goes to the Break Zone (not a "break" — broken stays false).
	# Setup boards (animate == false) are exempt, like summoning sickness, so test grounds may place a board directly.
	if animate and card != null and card.is_character():
		var unique_game: Node = get_parent()
		if unique_game != null and unique_game.has_method("would_be_unique_name_conflict") \
				and unique_game.would_be_unique_name_conflict(card):
			print("[Unique] %s is already on the field; the new copy goes to the Break Zone" % card.card_name)
			unique_game.send_off_field_card_to_break_zone(card)
			return
	var trans = card.global_transform
	card.reparent(self, false)
	card.position = Vector3.ZERO
	card.global_transform = trans

	# HISTORY. Recorded here because this is where a Character actually reaches the field — the "was played" event —
	# and `record` is false for the SETUP BOARD, where pre-placed cards were not played at all. Returning a card to
	# the field (Vanille) also lands here; it is logged as played, which is a known simplification.
	if record:
		var controller_name: String = card.controller
		var owner_id: int = 1 if controller_name == "player" else 2
		get_parent().record_action("%s %s was played" % [card.type, card.card_name], [], owner_id)

	# SUMMONING SICKNESS. A card that just entered the field cannot tap until its controller's next turn: it cannot
	# attack, a Backup cannot be tapped for mana, and a tap-costed skill is closed. Haste — printed or granted —
	# ignores it, and that single rule lives in Card.can_tap().
	#
	# SKIPPED FOR A SETUP BOARD (animate == false): pre-placed cards are meant to be playable from the first frame,
	# and they were not "just played". Card.turn_end() decrements the status, so one turn is the right duration.
	if animate:
		card.add_status_effect("summoning_sickness", 1)
	
	var target_node
	var target_array
	
	if card.type == 'Forward':
		target_array = opponent_front_cards if is_opponent else front_cards
		target_node = $OpponentFrontrowCard if is_opponent else $FrontrowCard
	else:  # Backup
		target_array = opponent_back_cards if is_opponent else back_cards
		target_node = $OpponentBackrowCard if is_opponent else $BackrowCard
	
	# Add card to appropriate array
	var n = target_array.size()
	target_array.append(card)
	register_conditional_effects(card)
	recompute_conditional_power()
	register_card_auras(card)
	register_power_per(card)
	# A card ENTERING can change a count for someone already in play (Jecht counts the opponent's Forwards), and
	# register_power_per only recomputes this card's own rules.
	recompute_power_per()
	
	# Calculate position
	var target_position = target_node.position
	if n % 2 == 0:
		target_position -= (n/2) * Vector3(0.8, 0, 0)
	else:
		target_position += ((n+1)/2) * Vector3(0.8, 0, 0)
	
	# The card is entering the field: normalise its look first (rotation, scale and
	# the power/damage readout). Without this a card played from hand keeps the
	# hand's fan tilt, because the reparent above deliberately preserves the whole
	# global transform so the travel animation starts where the card was.
	card.enter_zone(Card.Zone.FIELD)

	# ENTRY RULES (Ultimecia 152: "all Forwards other than Ultimecia enter the field dull"). Read from the board at
	# the moment of entry — nothing is registered, so a source that leaves the field simply stops being found. O(field)
	# per entry; a registry would be the optimisation if entry rules ever become numerous.
	if animate:
		_apply_entry_rules(card)

	if animate:
		var tween = create_tween().set_ease(Tween.EASE_OUT)
		tween.set_parallel(true)
		tween.tween_property(card, "position", target_position + Vector3(0, 0.8, 0), 0.3).set_delay(0.3)
		tween.set_trans(Tween.TRANS_BACK)
		# Same 1.2 as enter_zone: the pop must not leave the card at a different
		# size than a play that skipped the animation.
		tween.tween_property(card, "scale", Vector3.ONE*1.2, 0.5)
		tween.set_parallel(false)
		tween.tween_property(card, "position", target_position + Vector3(0, 2, 0), 0.6).set_delay(0.2)
		tween.tween_property(card, "position", target_position, 0.4)
		
		# Execute ETB after the ENTIRE tween sequence finishes
		tween.finished.connect(_on_tween_finished.bind(card))
	else:
		card.position = target_position
		GlobalVariables.refresh_mode()
	
func _on_tween_finished(card: Card):
	GlobalVariables.refresh_mode()
	#var instructions = card.create_instruction_from_json(card.card_effects['when_enter_field']['instructions'])
	execute_card_effect(card,"when_enter_field")
	#request_target_confirmation.emit()
	
func execute_card_attack():
	# DEFENCE IN DEPTH. Every caller already asks can_attack() — the human's click, the AI's choice, the blocker
	# gate — but this is the one function that turns an attacker into an attack, so summoning sickness must not be
	# bypassable by a future caller that forgets to ask. can_attack() is can_tap() plus "is a Forward".
	if attacker_card == null or not attacker_card.can_attack():
		return
	# A PARTY attacks with every member. Each one dulls unless it is Brave, and each one's "when attacks" triggers —
	# they attacked, even if only the party as a whole deals damage.
	var members: Array[Card] = attacking_party.duplicate()
	if members.is_empty():
		members.append(attacker_card)
	var attacking: Array[Card] = []
	for card in members:
		if card == null or not is_instance_valid(card) or not card.is_on_field():
			continue
		# A member that became unable to attack after formation simply does not attack; it cannot veto the party.
		if not card.can_attack():
			continue
		# BRAVE does not dull to attack, which is what lets a Brave Forward attack and still block — and attack again
		# on a later combat step the same turn. This is PER MEMBER, not per party.
		#
		# EXTRA ATTACKS: "Gilgamesh can attack twice this turn." The allowance is consumed here, and while it lasts the
		# card stays untapped, so the next attack step can declare it again. The LAST allowed attack taps normally.
		if card.extra_attacks > 0:
			card.extra_attacks -= 1
		elif not card.is_brave():
			card.tap()
		attacking.append(card)
		execute_card_effect(card, 'when_attack')
		# Board-wide "when a Forward you control attacks" watchers (Cloud 187). The event card is the attacker.
		trigger_event("forward_attacks", {"card": card})

	# "When <card> FORMS A PARTY AND ATTACKS..." — a different trigger from when_attack, and it needs a REAL party:
	# two or more members actually attacked (a party of one is just an ordinary attack, and the card text says
	# "forms a party"). Fired per member so each card's own effect resolves for itself; the effect acts on the whole
	# party through power_change_party().
	if attacking.size() >= 2:
		for card in attacking:
			execute_card_effect(card, 'when_party_attack')
		# AND the wider trigger: "when A PARTY YOU CONTROL attacks" — for cards that are watching the party rather
		# than riding in it (Celestia and Gippal are Backups/Forwards that may not be members at all).
		trigger_party_attacks(attacker_card.controller)

## Fire "a party you control attacked" for every card that side controls. Members already got their own
## `when_party_attack`; this is the watcher form, so both shapes exist and neither has to guess.
func trigger_party_attacks(controller: String) -> void:
	for card in get_all_cards():
		if card == null or not is_instance_valid(card):
			continue
		if card.controller != controller:
			continue
		if card.is_key_word_in_card_effect("when_party_attacks"):
			execute_card_effect(card, "when_party_attacks")

## Trigger-level conditions are evaluated by Game, because that is where the condition vocabulary lives
## (controls:, cast_this_turn:, party_has_named:). Field forwards rather than keeping a second copy of the rules.
func _trigger_condition_holds(condition: String) -> bool:
	var host: Node = get_parent()
	if host == null or not host.has_method("_condition_holds"):
		return true
	return bool(host.call("_condition_holds", condition))

## Fire "a party you control dealt damage to the opponent" (Andoria, Boko).
func trigger_party_deals_damage(controller: String) -> void:
	for card in get_all_cards():
		if card == null or not is_instance_valid(card):
			continue
		if card.controller != controller:
			continue
		if card.is_key_word_in_card_effect("when_party_deals_damage"):
			execute_card_effect(card, "when_party_deals_damage")

## Fire a board-wide event. Unlike the printed `when_*` keywords, these triggers live in a card's `triggers` array
## and watch something happening to the game rather than to that card:
##
##   damage_received   a player took damage                 context: {player_id}
##   card_left_field   a card was put into the Break Zone   context: {card}
##   summon_cast       a Summon was cast                    context: {card}
##   forward_attacks   a Forward attacked                   context: {card}
##
## A TRIGGERED ABILITY GOES ON THE STACK. The event only MATCHES and ENQUEUES here; `may`, target selection and the
## instructions all happen at resolution (Game._resolve_event_trigger), so either player can respond first and a
## "may" choice is made when the ability resolves, not when it triggers.
func trigger_event(event_name: String, context: Dictionary) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var cards: Array = get_all_cards().duplicate()
	for source in cards:
		if source == null or not is_instance_valid(source):
			continue
		var triggers = source.card_effects.get("triggers", [])
		if triggers is Dictionary:
			triggers = [triggers]
		if not (triggers is Array):
			continue
		for index in range(triggers.size()):
			var trigger = triggers[index]
			if not (trigger is Dictionary):
				continue
			if str(trigger.get("on", "")) != event_name:
				continue
			if not _event_filter_holds(source, trigger.get("filter", {}), context):
				continue
			var once: bool = bool(trigger.get("once_per_turn", false))
			var turn: int = int(host.get("turn_number"))
			var fire_key: String = "%d:%d:%d" % [source.get_instance_id(), index, turn]
			var fired: Dictionary = host.get("_event_triggers_fired")
			if once and fired != null and fired.has(fire_key):
				continue
			if once and fired != null:
				fired[fire_key] = true
			stack.enqueue_event_trigger(source, trigger, context)

## A trigger's filter is criteria on the event card, except for events with no card (damage_received), where only the
## controller comparison makes sense. "your"/"opponent" are relative to the trigger owner.
func _event_filter_holds(source: Card, filter, context: Dictionary) -> bool:
	if not (filter is Dictionary) or filter.is_empty():
		return true
	var event_card: Card = context.get("card", null)
	if event_card != null and is_instance_valid(event_card):
		return event_card.matches_criteria(filter, source)
	var wanted: String = str(filter.get("controller", ""))
	if wanted == "":
		return true
	var owner_id: int = 1 if source.controller == "player" else 2
	var event_id: int = int(context.get("player_id", 0))
	if wanted in ["your", "self", "mine", "player"]:
		return event_id == owner_id
	if wanted in ["opponent", "enemy", "theirs"]:
		return event_id != owner_id and event_id != 0
	return false

func _event_targets(trigger: Dictionary, source: Card, context: Dictionary) -> Array:
	var mode: String = str(trigger.get("target", "source"))
	if mode == "event":
		var event_card: Card = context.get("card", null)
		return [event_card] if event_card != null and is_instance_valid(event_card) else []
	if mode == "none":
		return []
	return [source]

## "The Forwards forming a party you control gain Brave" (Gippal). Asked by Card.is_brave(), because that is the
## predicate the attack path already reads per member.
func party_grants_brave(card: Card) -> bool:
	if card == null or attacking_party.size() < 2 or not attacking_party.has(card):
		return false
	for c in get_all_cards():
		if c != null and is_instance_valid(c) and c.controller == card.controller and c.card_effects.has("party_brave"):
			return true
	return false
	
func end_phase_cleanup():
	# End Phase cleanup: remove all damage from every card on the field and
	# expire "until end of turn" effects. (No end-of-turn priority window
	# exists yet, so this runs immediately on entering the End Phase.)
	for c in get_all_cards():
		c.turn_end()
func try_activate_from_field(card: Card) -> void:
	if not "skill" in card.card_effects:
		return
	var skills: Array = card.card_effects["skill"]
	if skills.is_empty():
		return
	# ONE ENTRY POINT. A single ability activates immediately; two or more open the skill picker modal, which shows
	# each ability's text (see scripts/skill_choice.gd). The old 3D "Skill" buttons are no longer used for this.
	begin_skill_activation(card, -1)

## True while the LOCAL player holds the window. Holding a card you *could* activate is not the
## same as being allowed to activate it: while the OPPONENT holds priority the input mode is
## still FREE/INSTANT_SPEED_TIME, so the mode alone cannot answer this question. A finished
## match is not a window either.
func has_priority() -> bool:
	var game: Node = get_parent()
	if game == null:
		return false
	if bool(game.get("match_over")):
		return false
	return int(game.get("priority_holder")) == 1

## The authoritative "this card's effect can be activated right now" gate: your card, YOUR
## WINDOW, untapped, with an activatable skill, in a moment where acting is allowed (FREE or
## INSTANT_SPEED_TIME — no targeting, payment or declaration modal open).
##
## begin_skill_activation() uses this as its precondition AND the green availability ring is
## driven from it, so the cue and the action can never disagree. Any condition added here
## therefore tightens both at once.
func can_activate_now(card: Card) -> bool:
	if card == null or card.controller != "player":
		return false
	if not has_priority():
		return false
	var mode = GlobalVariables.get_player_mode()
	if mode != GlobalVariables.Player_Mode.FREE and mode != GlobalVariables.Player_Mode.INSTANT_SPEED_TIME:
		return false
	# A TAPPED CARD CAN STILL USE A NON-TAP ABILITY. The tap rule belongs to the cost, not to the card: Gilgamesh's
	# 《雷》《雷》 power pump has no dull cost, so it must stay available after he has attacked. The same reasoning
	# applies to summoning sickness: can_tap() is asked per ability, below, only when the ability asks to tap.
	if not "skill" in card.card_effects:
		return false
	var skills: Array = card.card_effects["skill"]
	if skills.is_empty():
		return false
	# AN S COST THAT CANNOT BE PAID IS NOT AN AVAILABLE ABILITY. Without this the activation TAPPED the source and then
	# aborted silently — and because the abort untaps again, every further click re-tapped it, which reads as "the card
	# just taps and nothing happens". Checking here means the card is simply not offered (no green ring), and
	# begin_skill_activation() refuses it for the same reason, so the tap never happens.
	#
	# ONE USABLE ABILITY IS ENOUGH for the card to be offered. With several abilities the card is available if ANY of
	# them can be paid; the unpayable ones are shown disabled in the picker rather than hiding the card entirely.
	for def in skills:
		# "You can only use this ability during your turn" (Devout 48). Checked PER ABILITY, because a card may have
		# one time-restricted skill and one that is always available.
		var owner_id_now: int = 1 if card.controller == "player" else 2
		if bool(def.get("only_your_turn", false)) and int(get_parent().turn_owner) != owner_id_now:
			continue
		# "You can only use this ability while <card> is blocking." A per-ability gate, like only_your_turn:
		# the same card may have another ability that is always available.
		if bool(def.get("only_if_blocking", false)) and not card.status_effects.has("blocking"):
			continue
		# A tap cost needs a card that can actually tap; a non-tap ability does not.
		if bool(def.get("tap", false)) and not card.can_tap():
			continue
		# "You can only use this ability if you have received 4 points of damage or more" (Gilgamesh 207).
		if def.has("only_if_damage_received") \
				and _damage_received_by(card) < int(def["only_if_damage_received"]):
			continue
		if bool(def.get("s_cost", false)) and not hand.has_card_matching_criteria({"is_named": card.card_name}):
			continue
		# A sacrifice cost with nothing to sacrifice is not an available ability either.
		if def.has("sacrifice") and _sacrifice_candidates(def["sacrifice"], card).is_empty():
			continue
		# Same for a discard cost with too few cards in hand.
		if int(def.get("discard", 0)) > 0 and (hand == null or hand.cards.size() < int(def.get("discard", 0))):
			continue
		# An ability that targets the STACK is only worth offering while there is something there to target.
		var ct = def.get("choose_target", {})
		if ct is Dictionary and str(ct.get("in", "")) == "stack" \
				and not has_viable_target(ct, card, "Ability", "stack"):
			continue
		return true
	return false

## Damage in the controller's Damage Zone. Used by "you can only use this ability if you have received N damage"
## (Gilgamesh 207); the zone holds one card per point, so its count is the number.
func _damage_received_by(card: Card) -> int:
	var game: Node = get_parent()
	if game == null:
		return 0
	var side = game.side_for(1 if card.controller == "player" else 2)
	return side.damage_count() if side != null else 0

## Cards that could be paid for a `"sacrifice": {...}` skill cost. Criteria are read from the SOURCE's perspective, so
## `controller: "player"` means the activating card's controller.
func _sacrifice_candidates(criteria: Dictionary, source: Card) -> Array:
	var out: Array = []
	for c in get_all_cards():
		if c != null and is_instance_valid(c) and c.matches_criteria(criteria, source):
			out.append(c)
	return out

## Green ring: "you may activate this right now" — your cards only, and gone the moment a modal
## takes the moment away. It is DERIVED state with many causes (the input mode, a card's tapped
## state, which cards are on the field), so it is POLLED rather than hooked to one trigger; the
## card setters are guarded, so an unchanged card costs a bool comparison.
const AVAILABILITY_POLL := 0.15
var _availability_timer: float = 0.0

func _process(delta: float) -> void:
	_availability_timer += delta
	if _availability_timer < AVAILABILITY_POLL:
		return
	_availability_timer = 0.0
	refresh_available_effects()

func refresh_available_effects() -> void:
	for card in get_all_cards():
		card.set_available_highlight(can_activate_now(card))

## Activate an ability. `skill_index < 0` means ASK: one ability activates directly, two or more open the picker
## modal and wait for the choice. Explicit indexes stay supported (probes, and any future "activate ability N").
func begin_skill_activation(card: Card, skill_index: int = -1) -> void:
	if not can_activate_now(card):
		return
	var skills: Array = card.card_effects["skill"]
	if skills.is_empty():
		return
	if skill_index < 0:
		skill_index = 0
		if skills.size() > 1:
			# WHICH ENTRIES ARE PAYABLE RIGHT NOW. An S ability needs a card of the same name in hand; the picker
			# shows it disabled instead of letting the player pick an activation that can only abort.
			var usable: Array = []
			for def in skills:
				var turn_ok: bool = (not bool(def.get("only_your_turn", false)) \
					or int(get_parent().turn_owner) == (1 if card.controller == "player" else 2)) \
					and (not bool(def.get("only_if_blocking", false)) or card.status_effects.has("blocking")) \
					and (not bool(def.get("tap", false)) or card.can_tap()) \
					and (not def.has("only_if_damage_received")
						or _damage_received_by(card) >= int(def["only_if_damage_received"]))
				var can_pay: bool = turn_ok and (not bool(def.get("s_cost", false)) \
					or hand.has_card_matching_criteria({"is_named": card.card_name}))
				if can_pay and def.has("sacrifice"):
					can_pay = not _sacrifice_candidates(def["sacrifice"], card).is_empty()
				if can_pay and int(def.get("discard", 0)) > 0:
					can_pay = hand != null and hand.cards.size() >= int(def.get("discard", 0))
				usable.append(can_pay)
			var owner_id: int = 1 if card.controller == "player" else 2
			var agent: Agent = get_parent().agent_for(owner_id)
			if agent == null:
				return
			skill_index = await agent.choose_skill(owner_id, card, skills, usable)
			# The picker is awaited, so anything could have happened behind it. Re-check before spending anything.
			if not can_activate_now(card):
				return
		if skill_index < 0:
			return
	if skill_index >= skills.size():
		return
	if not stack.add_skill_activation_proxy(card, skill_index):
		return
	assistant.clear_payment_accumulator()
	var def: Dictionary = skills[skill_index]
	# TAP THE SOURCE NOW, BEFORE THE MANA STEP. Tapping is part of the ability's cost, so it belongs at the moment
	# of activation rather than at stack commit.
	#
	# It used to be applied by Stack._apply_skill_source_tap_from_proxy(), reached only from
	# commit_skill_activation_costs_if_pending() — which runs AFTER the mana has been chosen. So for the whole
	# payment step the source was still untapped and could be selected as mana for its own ability: paying the Red
	# Mage's skill with the Red Mage. Tapping it here removes it from the pool by the same rule that already keeps
	# every other tapped Backup out of it.
	#
	# Stack._clear_skill_proxy() undoes this when the player backs out, so the tap is only really spent once the
	# activation commits.
	if def.get("tap", false) and not card.tapped:
		card.tap()
	# PUT-INTO-THE-BREAK-ZONE COST (Mystic 96). Paid at activation like the S discard, and chosen by the owner through
	# the agent seam, so the human gets a picker and the AI picks for itself. A cancelled pick aborts the whole
	# activation: the proxy is cleared (which refunds the tap) and nothing is sacrificed.
	var owner_id: int = 1 if card.controller == "player" else 2
	var sacrifice: Dictionary = def.get("sacrifice", {})
	if not sacrifice.is_empty():
		var picked: Card = null
		if bool(sacrifice.get("is_source", false)):
			# "Put THIS card into the Break Zone" — no choice to make, and no reason to ask an agent.
			picked = card if card.matches_criteria(sacrifice, card) else null
		else:
			var candidates: Array = _sacrifice_candidates(sacrifice, card)
			if not candidates.is_empty():
				picked = await get_parent().agent_for(owner_id).choose_sacrifice(owner_id, candidates)
		if picked == null:
			stack.call("_clear_skill_proxy")
			return
		print("[Sacrifice] %s -> Break Zone" % picked.card_name)
		get_parent().put_card_into_graveyard(picked)
	# DISCARD AS A COST (Ninja 78). The owner picks which cards leave their hand, through the same agent seam the
	# discard effects use — so the human gets the hand picker and the AI chooses for itself. A refused pick aborts the
	# activation and clears the proxy, which is what keeps "cancel" from costing a card.
	var discard_count: int = int(def.get("discard", 0))
	if discard_count > 0:
		var owner_hand: Hand = get_parent().hand_for(owner_id)
		for _i in range(discard_count):
			if owner_hand == null or owner_hand.cards.is_empty():
				stack.call("_clear_skill_proxy")
				return
			var discarded: Card = await get_parent().agent_for(owner_id).choose_discard(
				owner_id, owner_hand.cards.duplicate())
			if discarded == null:
				stack.call("_clear_skill_proxy")
				return
			print("[Discard] %s (cost)" % discarded.card_name)
			owner_hand.discard_card(discarded)
	if def.get("s_cost", false):
		# Special ability (S): first discard a card sharing a name with the
		# source, then the regular mana payment step follows.
		stack.begin_s_cost_selection(card, skill_index)
		return
	var cost: Dictionary = def.get("cost", {})
	if cost_is_free(cost):
		# NOTHING TO PAY, SO NO PAYMENT STAGE — and no Confirm to press on an empty screen before anything can happen.
		# This is exactly the branch the Confirm button would have taken, so nothing is skipped but the modal.
		continue_skill_activation_after_mana(stack.skill_activation_proxy)
		return
	card_activated_ability.emit(cost)

## A mana cost with nothing in it — absent, empty, or all zeroes. Those cost the player nothing, so showing them a payment
## modal asks them to confirm that they intend to pay nothing.
func cost_is_free(cost: Dictionary) -> bool:
	for key in cost:
		if int(cost[key]) > 0:
			return false
	return true

func continue_skill_activation_after_mana(_proxy: Card) -> void:
	if _proxy == null or _proxy.effect_source == null:
		return
	var src: Card = _proxy.effect_source
	var idx: int = _proxy.skill_activation_index
	if idx < 0 or not "skill" in src.card_effects:
		return
	var skills: Array = src.card_effects["skill"]
	if idx >= skills.size():
		return
	var def: Dictionary = skills[idx]
	var choose_target = def.get("choose_target", null)
	if choose_target:
		# The arc starts from the PROXY in the stack, not from the card on the field:
		# that is the object the player is actually resolving, and it is where the
		# arrow should appear to come from. The proxy carries the same controller, and
		# source_kind below is what the protection rules read, so targeting behaviour
		# is unchanged.
		request_target(choose_target, _proxy, true, "Ability")
	else:
		GlobalVariables.refresh_mode()
		assistant.generate_confirm_button(func(): stack.confirm_skill_without_target_then_priority())
	
func execute_card_effect(card,keyword):
	if( not card.is_key_word_in_card_effect(keyword)):
		return
	# A TRIGGER-LEVEL CONDITION, checked BEFORE anything is put on the stack. Instruction conditions cannot do this
	# job: a conditional triggered ability would still choose a target and queue an empty effect. "When <card> forms a
	# party WITH X and attacks" is the case that needs it.
	var trigger_condition: String = str(card.card_effects.get(keyword, {}).get("condition", ""))
	if trigger_condition != "" and not _trigger_condition_holds(trigger_condition):
		return
	add_card_effect_to_stack.emit(card.id,keyword,card)
	# Most elegant single-line solution
	var choose_target_criteria = card.card_effects.get(keyword, {}).get('choose_target', null)
	
	# The effect RESOLVES as a card in the stack — Stack.create_card() makes that copy in
	# response to the signal above, synchronously, so it is already there. That copy is the
	# object the player is resolving, so the targeting arc must originate from IT and not
	# from the card sitting on the field.
	var stack_card: Card = _stack_effect_card_for(card)
	if choose_target_criteria:
		var source_for_target: Card = stack_card if stack_card != null else card
		# NO LEGAL TARGET MEANS NO TARGETING SESSION. "You may deal it damage" style triggers fire when nothing is
		# eligible (no dull Forward, say) — opening an empty session there would strand the effect with no way to
		# finish it, so the trigger simply adds an effect that resolves with nothing to do.
		var domain: String = "field"
		if choose_target_criteria is Dictionary:
			domain = str(choose_target_criteria.get("in", "field"))
		if has_viable_target(choose_target_criteria, source_for_target, "Ability", domain):
			request_target(choose_target_criteria, source_for_target, false, "Ability")

## The stack's copy of the effect triggered by `source`, if it exists yet.
func _stack_effect_card_for(source: Card) -> Card:
	var game: Node = get_parent()
	if game == null:
		return null
	var s: Variant = game.get("stack")
	if s == null or s.cards == null:
		return null
	var found: Card = null
	for c in s.cards:
		if c.effect_source == source:
			found = c
	return found
func get_all_cards() -> Array[Card]:
	return front_cards + back_cards + opponent_front_cards + opponent_back_cards

func get_front_cards_for(controller_name: String) -> Array[Card]:
	# Forwards of one side. Agents use this for attack / block decisions.
	return front_cards if controller_name == "player" else opponent_front_cards

func get_back_cards_for(controller_name: String) -> Array[Card]:
	# Backups of one side: the AI taps these to pay card costs.
	return back_cards if controller_name == "player" else opponent_back_cards

func untap_cards_for(controller_name: String) -> void:
	# Active Phase untaps only the turn player's cards.
	var cards: Array[Card] = (front_cards + back_cards) if controller_name == "player" else (opponent_front_cards + opponent_back_cards)
	for card in cards:
		# FROZEN: "does not activate during its controller's next Active Phase."
		#
		# The status is CONSUMED here rather than counted down in turn_end(). A duration would be the wrong clock:
		# turn_end() ticks every card once per turn regardless of who owns it, so a freeze applied on the victim's
		# OWN turn would expire before their next Active Phase, and the same keyword would behave differently
		# depending on when it was applied. Consuming it at the untap it denies is exact in both directions, and it
		# does not stack - being Frozen twice still skips one Phase, because the second erase is a no-op.
		#
		# It does NOT block untap_targets(): "Activate" effects still work on a Frozen card. Freeze denies the
		# Active Phase, not activation.
		# "WILL NOT ACTIVATE DURING YOUR NEXT ACTIVE PHASE" (Kain) is the same clock as Freeze: a status consumed by
		# the untap it denies, never counted down at End Phase.
		if card.status_effects.has("skip_next_active"):
			card.status_effects.erase("skip_next_active")
			print("[Skip] %s does not activate" % card.card_name)
			continue
		if card.status_effects.has("frozen"):
			card.status_effects.erase("frozen")
			print("[Freeze] %s does not activate" % card.card_name)
			continue
		card.untap()
		
func request_target(targeting_criteria, card: Card, allow_cancel: bool = false, source_kind: String = ""):
	# Always start a targeting session fresh. Leftover target_card from a
	# previous session made set_target_card() ignore clicks (stuck UI).
	targeting_allow_cancel = allow_cancel
	target_card = null
	source_card = card
	# A SESSION MAY ASK FOR MORE THAN ONE TARGET. `choose_target` may carry a "count"; absent (or anything that is not a
	# Dictionary) means ONE, and one behaves exactly as it always has — including going straight to Confirm on the pick.
	# See `targeting_picked`.
	#
	# `count` IS A SESSION KEY, NOT A PROPERTY OF A CARD, so it is stripped before anything is matched against it.
	# Card.matches_criteria() treats every key as a METHOD NAME ON CARD and errors out on anything else — so leaving
	# "count" in the criteria made has_method("count") false, which made every candidate illegal and meant no pick could
	# ever be recorded. That is a silent failure: the ring simply never lit.
	targeting_source_kind = source_kind
	targeting_blocks = targeting_criteria if targeting_criteria is Array else [targeting_criteria]
	targeting_block_index = 0
	targeting_block_start = 0
	targeting_picked.clear()
	_chosen_notified = false
	# EVERY arc from the last session goes, not just the aiming one: a multi-target session leaves several behind.
	for old in targeting_arrows:
		if old != null and is_instance_valid(old):
			old.queue_free()
	targeting_arrows.clear()
	if arrow:
		arrow.queue_free()
		arrow = null
	reset_targets()
	# The stack's review link draws the same arrow shape and paints the same aura, so it has to
	# let go of both before this session claims them.
	var stack_node = get_parent().get("stack")
	if stack_node != null:
		stack_node.release_target_display()
	print("[Targeting] request_target source=%s stages=%d" % [card.card_name, targeting_blocks.size()])
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.TARGET)
	_begin_target_block(0)
	if allow_cancel:
		assistant.prepare_targeting_phase_cancel()

## WHICH BOARD a criteria block looks at.
func _block_domain(block) -> String:
	return str(block.get("in", "field")) if block is Dictionary else "field"

## Start pick stage `index`. One stage is one criteria block; a normal single-target effect has exactly one, and
## `count` still means "this many picks inside THIS stage" (Aerith's "up to 3 Backups").
##
## The stage's first pick index is the sum of the earlier stages' counts, not `targeting_picked.size()`: that is what
## makes stepping back into a previous stage ask for exactly the right number of picks again.
func _begin_target_block(index: int) -> void:
	targeting_block_index = index
	var start: int = 0
	for i in range(index):
		var previous = targeting_blocks[i]
		start += maxi(1, int(previous.get("count", 1))) if previous is Dictionary else 1
	targeting_block_start = start
	var block = targeting_blocks[index] if index >= 0 and index < targeting_blocks.size() else {}
	targeting_criteria_now = block
	targeting_count = 1
	targeting_domain = _block_domain(block)
	if block is Dictionary:
		targeting_count = maxi(1, int(block.get("count", 1)))
		if block.has("count") or block.has("in"):
			targeting_criteria_now = block.duplicate()
			targeting_criteria_now.erase("count")
			targeting_criteria_now.erase("in")
	target_card = null
	_spawn_aiming_arrow(source_card)
	set_viable_targets(targeting_criteria_now, source_card, targeting_source_kind)
	# set_viable_targets() clears every ring; give the picks already recorded theirs back. The colour follows the
	# CHOOSER, not the card's owner: when you are the one picking, your picks are orange even on the opponent's board.
	var local_chooser: bool = source_card == null or source_card.controller == "player"
	for taken in targeting_picked:
		taken.set_valid_target(false, false)
		if local_chooser:
			taken.set_selected_highlight(true)
		else:
			taken.set_targeted_highlight(true)
	# A non-local owner resolves this stage through its agent instead of waiting for clicks nobody will make.
	var owner_id: int = 1 if source_card != null and source_card.controller == "player" else 2
	var agent: Agent = get_parent().agent_for(owner_id)
	if agent != null and not (agent is LocalAgent):
		agent.choose_target(owner_id, source_card, targeting_criteria_now)

## A fresh arc, aimed at the pointer from `from`.
##
## THE INVARIANT this section maintains, and that everything here depends on:
##
##     targeting_arrows is ONE ARC PER PICK, in pick order, PLUS ONE AIMING ARC at the end.
##
## So targeting_arrows[i] is the arc locked on targeting_picked[i], and the last element is the one following the pointer.
## When the session is FULL there is no aiming arc — the last element is the final pick's — and _aim_with_current() adds
## one after a step back re-opens it. Breaking this is invisible until a step back removes the wrong arc, or two at once,
## or leaves one on screen: the arrows and the state quietly stop agreeing.
func _spawn_aiming_arrow(from: Card) -> void:
	var fresh = ballistic_arrow_scene.instantiate()
	arrow = fresh
	add_child(fresh)
	fresh.set_is_aiming_from_card(true, from)
	targeting_arrows.append(fresh)

## Point the aiming arc at the pointer from `source_card`, spawning one when the picks have caught up with the arcs.
## The ONLY place `arrow` is assigned besides a spawn, so the invariant cannot drift out from under it.
func _aim_with_current() -> void:
	while targeting_arrows.size() <= targeting_picked.size():
		_spawn_aiming_arrow(source_card)
	var pointing = targeting_arrows.back()
	arrow = pointing
	if pointing != null and is_instance_valid(pointing):
		# It must not stay locked: at a full session the last element is a PICK's arc, and borrowing it would set that
		# pick's arrow following the pointer and leave its card bare.
		pointing.locked = false
		pointing.set_is_aiming_from_card(true, source_card)

## Drop one pick: its ring, its arc, and its claim on being the current target.
##
## THE ARC AT `at` IS THAT PICK'S, by the invariant above — so exactly ONE arrow leaves the board. `at + 1` was wrong,
## and freeing the aiming arc separately in the caller was wrong too: between them the array collected dead arcs, its
## indexes stopped matching the picks, and a single step back could take two arrows off at once.
func _drop_pick(at: int) -> void:
	var picked: Card = targeting_picked[at]
	targeting_picked.remove_at(at)
	if at < targeting_arrows.size():
		var spent = targeting_arrows[at]
		targeting_arrows.remove_at(at)
		if spent != null and is_instance_valid(spent):
			spent.queue_free()
	if picked != null and is_instance_valid(picked):
		picked.set_selected_highlight(false)
		picked.set_targeted_highlight(false)
	if picked == target_card:
		target_card = null
	# STEPPING BACK ACROSS A STAGE BOUNDARY. The pick just removed was the FIRST of the current stage, so the
	# previous stage becomes current and asks for its own criteria again.
	if targeting_block_index > 0 and at == targeting_block_start:
		_begin_target_block(targeting_block_index - 1)
		return
	# It becomes legal again: the card is no longer spoken for, and the ring it lost has to come back.
	set_viable_targets(targeting_criteria_now, source_card, targeting_source_kind)
	for taken in targeting_picked:
		taken.set_valid_target(false, false)
		# ...and the picks that are STILL picked keep their rings, for the same reason as in set_target_card(): the call
		# above clears them all.
		if taken.controller == "opponent":
			taken.set_targeted_highlight(true)
		else:
			taken.set_selected_highlight(true)
	# Re-establish the invariant before anything reads the arrows again.
	_aim_with_current()

func set_target_card(card: Card):
	# A click only counts when the candidate is a legally valid target.
	# is_valid_target is set by set_viable_targets() (criteria + protection).
	if not card.is_valid_target:
		push_warning("[Targeting] %s is not a valid target" % card.card_name)
		return
	# A FULL SESSION IGNORES FURTHER PICKS. It is complete at `count`, and a click after that used to be taken anyway —
	# leaving one more pick than the session had arcs for, which is a state nothing downstream could match back up.
	# Confirm and a right-click are the two ways on from here.
	if targeting_count > 1 and targeting_picked.size() >= targeting_count:
		return
	# Blue and orange are the LOCAL player's vocabulary: "legal" and "you picked this".
	# When the opponent is the one choosing, the picked card is shown in RED instead —
	# along with their arc, so an incoming effect is readable while it is on the stack.
	var local_chooser: bool = source_card == null or source_card.controller == "player"
	# Clicking another valid target MOVES the selection — and the ring with it — rather
	# than being ignored, so either player can change their mind.
	if target_card != null and is_instance_valid(target_card):
		target_card.set_selected_highlight(false)
		target_card.set_targeted_highlight(false)
	target_card = card
	if local_chooser:
		card.set_selected_highlight(true)
	else:
		card.set_targeted_highlight(true)
	print("[Targeting] target selected: ", card.card_name)
	arrow.lock_arc(card.get_global_face_centre())
	targeting_picked.append(card)
	# THIS STAGE IS FULL: either the next stage takes over (Hades: Forward, then Backup) or the session is complete.
	var stage_full: bool = targeting_picked.size() >= targeting_block_start + targeting_count
	if stage_full and targeting_block_index + 1 < targeting_blocks.size():
		print("[Targeting] stage %d done — asking for stage %d" % [
			targeting_block_index + 1, targeting_block_index + 2])
		_begin_target_block(targeting_block_index + 1)
		return
	if targeting_picked.size() >= targeting_count:
		request_target_confirmation.emit(target_card, targeting_allow_cancel)
		return
	# MORE PICKS TO COME. The arc stays where it landed — that IS the record of the pick — a new one takes over the
	# aiming, and the card just taken leaves the legal set so the same Backup cannot be chosen twice. Its orange ring
	# stays: set_valid_target() only owns the blue prompt glow.
	print("[Targeting] %d of %d picked — aiming for the next" % [targeting_picked.size(), targeting_count])
	target_card = null
	_spawn_aiming_arrow(source_card)
	set_viable_targets(targeting_criteria_now, source_card, targeting_source_kind)
	for taken in targeting_picked:
		taken.set_valid_target(false, false)
		# AND GIVE EVERY PICKED CARD ITS RING BACK. The set_viable_targets() call just above clears the pick highlight on
		# EVERY card — that is how a session is supposed to start — so using it to refresh the legal set after each pick
		# wiped the ring off all the earlier picks and left only the newest one lit.
		if taken.controller == "opponent":
			taken.set_targeted_highlight(true)
		else:
			taken.set_selected_highlight(true)
	# CONFIRM IS AVAILABLE NOW, WITH FEWER PICKS THAN THE COUNT. The card says "choose UP TO 3", so stopping early has to
	# be possible — and the aiming arc stays, so the player can equally keep going and reach the full count, which ends
	# the session by itself. Only the last slot is ever mandatory.
	request_target_confirmation.emit(
		targeting_picked.back() if not targeting_picked.is_empty() else null, targeting_allow_cancel)

## ONE STEP BACK, for a right-click, and it works from ANY point in the session.
##
## ANY pick steps back — INCLUDING THE LAST ONE ONCE THE COUNT IS FULL. The first version only stepped back while fewer
## than `count` had been picked, so once three of three were chosen the guard failed, control fell through to the
## single-target path below, and that path found `target_card` already null and returned without doing anything. The
## picks were never taken off the list, which is the "it cancels the last target and then the button stops working"
## report. Stepping back re-opens the session: a new aiming arc appears and the picks that remain are still picks.
func clear_target_selection() -> void:
	if targeting_count > 1 and not targeting_picked.is_empty():
		# ONE call. `_drop_pick` removes that pick's arc AND re-establishes the aiming one (see _aim_with_current).
		# Also freeing the aiming arc here, as this used to, is what let a single step back take TWO arrows off the
		# board — and left a dead arc in the array, so the indexes stopped matching the picks.
		_drop_pick(targeting_picked.size() - 1)
		print("[Targeting] back to %d of %d" % [targeting_picked.size(), targeting_count])
		if not targeting_picked.is_empty():
			# Picks remain, so finishing early is still allowed: Confirm stays on offer next to the aiming arc.
			target_card = targeting_picked.back()
			request_target_confirmation.emit(target_card, targeting_allow_cancel)
		elif assistant != null:
			target_card = null
			if targeting_allow_cancel:
				assistant.prepare_targeting_phase_cancel()
			else:
				assistant.hide_buttons()
		return
	if target_card == null or not is_instance_valid(target_card):
		return
	if source_card != null and target_card == source_card:
		return
	target_card.set_selected_highlight(false)
	target_card.set_targeted_highlight(false)
	print("[Targeting] selection cleared — aiming again")
	target_card = null
	if arrow != null and is_instance_valid(arrow):
		# `locked` is what froze the arc on the pick (see lock_arc); dropping it and re-aiming puts the arc back on the
		# pointer. Both, because unlocking alone leaves the arc pointing at wherever the pick was.
		arrow.locked = false
		arrow.set_is_aiming_from_card(true, source_card)
	if assistant != null:
		if targeting_allow_cancel:
			assistant.prepare_targeting_phase_cancel()
		else:
			assistant.hide_buttons()
	
func set_viable_targets(target_criteria, source: Card = null, source_kind: String = ""):
	# The blue ring means "the game is asking YOU". When the OPPONENT is the one choosing,
	# their legal options are not our business. The flag still goes on — their agent selects
	# by it — but the glow stays off, so the only thing we see is the card they pick, which
	# set_target_card() marks red.
	var glow: bool = source == null or source.controller == "player"
	var candidates: Array = _target_candidates()
	var legal: Array = []
	for card in candidates:
		if _card_matches_criteria(card, target_criteria, source, source_kind):
			legal.append(card)
	# "Summons or abilities of your opponent must choose Cecil if possible." If at least one legal candidate demands
	# to be chosen, the legal set collapses to those candidates. If none do, every legal candidate stays available.
	var allowed: Array = legal
	if source != null:
		var mandatory: Array = []
		for card in legal:
			if card.must_be_chosen_by(source, source_kind):
				mandatory.append(card)
		if not mandatory.is_empty():
			allowed = mandatory
	for card in candidates:
		var is_targetable: bool = allowed.has(card)
		# A fresh session starts with nothing picked: clear any leftover ring.
		card.set_selected_highlight(false)
		card.set_targeted_highlight(false)
		# The prompt glow IS the indicator — no separate marker is spawned on top of
		# each candidate.
		card.set_valid_target(is_targetable, glow)

## Live "do you control a card matching this?" query for conditional printed rules (Rikku 201). `source` resolves
## controller-relative words in the criteria; `controller_name` is whose board is being searched.
func controls_matching(controller_name: String, criteria: Dictionary, source: Card = null) -> bool:
	for card in get_all_cards():
		if card.controller != controller_name:
			continue
		if card.matches_criteria(criteria, source):
			return true
	return false

## WHERE THIS SESSION'S CANDIDATES COME FROM. The stack is a second target domain, for effects that choose a Summon
## before it resolves (Summoner 53). `stack.cards` is copied because cancelling a Summon mutates it mid-session.
func _target_candidates() -> Array:
	if targeting_domain == "stack" and stack != null:
		return stack.cards.duplicate()
	return get_all_cards()

func has_viable_target(target_criteria, source: Card = null, source_kind: String = "", domain: String = "field") -> bool:
	# Used before casting a Summon (no legal target = cannot cast) and before offering an ability that needs a target.
	# EVERY STAGE MUST BE SATISFIABLE. "Choose 1 Forward and 1 Backup" is mandatory on both, so a board missing one
	# of them makes the card illegal to play at all (Advanced Rules: mandatory targets at casting time).
	if target_criteria is Array:
		for block in target_criteria:
			if not has_viable_target(block, source, source_kind, _block_domain(block)):
				return false
		return true
	var candidates: Array = stack.cards.duplicate() if domain == "stack" and stack != null else get_all_cards()
	for card in candidates:
		if _card_matches_criteria(card, target_criteria, source, source_kind):
			return true
	return false

func _card_matches_criteria(card: Card, target_criteria: Dictionary, source: Card = null, source_kind: String = "") -> bool:
	# Legality has two parts: the effect's choose_target criteria (properties of
	# the candidate) and the candidate's own protection against this source.
	# source_kind overrides the source card's own kind, because ability targeting
	# is requested with the field card, which carries no effect_kind.
	#
	# The SOURCE is passed through: an exclude block may say "other than this card", and the relative controller keys
	# ("one of yours") need to know whose effect is asking.
	if not card.matches_criteria(target_criteria, source):
		return false
	if not card.can_be_chosen_by(source, source_kind):
		return false
	# A SHIELD GRANTED BY ANOTHER CARD (Dajh -> Sazh, Serah -> Snow). The printed rule above is self-contained; this one
	# is a continuous field effect, so the board has to be asked.
	#
	# ONLY THE CHOOSING GATE. "All your Backups" effects still hit a card that cannot be chosen — it was never chosen —
	# which is why `_cards_matching` (apply_effect) deliberately does NOT ask this.
	if source != null and is_protected_from_being_chosen(card, source, source_kind):
		return false
	return true
		
func reset_targets():
	# Every meaning a targeting session can leave behind: the blue prompt, the ORANGE pick, and
	# the opponent's red reveal. The orange is the one that leaked — it was set on the click and
	# only ever cleared by the *next* session starting, so an ability that resolved and was not
	# followed by another targeting left its target glowing orange for the rest of the match.
	for card in get_all_cards():
		# Through the setter, so the "targetable" glow clears with the flag.
		card.set_valid_target(false)
		card.set_selected_highlight(false)
		# ...and the opponent's red ring with it.
		card.set_targeted_highlight(false)

## Drop only the red "the opponent chose this" rings, leaving the selection state alone.
## Called when the stack has fully resolved — the reveal is spent — rather than never, which
## would leave the ring to outlive the effect.
func clear_targeted_highlights() -> void:
	for card in get_all_cards():
		card.set_targeted_highlight(false)

func remove_card(card):
	unregister_conditional_effects(card)
	unregister_card_auras(card)
	unregister_power_per(card)
	front_cards.erase(card)
	back_cards.erase(card)
	opponent_front_cards.erase(card)
	opponent_back_cards.erase(card)
	recompute_conditional_power()
	refresh_auras()
	recompute_power_per()
	# A member leaving the field leaves the party; fewer than two members disbands it. Done here because every way
	# off the field (break, exile, return, effect) ends in remove_card, so no caller has to remember.
	#
	# drop_party_member() first, unconditionally: this runs BEFORE the card's zone changes, so a field check would
	# still say FIELD and the departing card would stay in the party. prune_party() then clears any other stale ones.
	drop_party_member(card)
	prune_party()

## Conditional continuous effects ("if you control X, this gains power").
## Re-evaluated only when the field composition changes: play_card/remove_card.
var _conditional_effects: Array[Dictionary] = []

func register_conditional_effects(card: Card) -> void:
	if "conditional_power" in card.card_effects:
		for effect in card.card_effects["conditional_power"]:
			_conditional_effects.append({
				"source": card,
				"condition": effect.get("condition", {}),
				"value": int(effect.get("value", 0)),
				# EACH RULE KEEPS ITS OWN LEDGER. A card may have two conditional powers (Rikku 201: +2000 for
				# Yuna, +2000 for Paine); one shared current_conditional_bonus made them overwrite each other, so
				# the second always undid the first.
				"granted": 0,
			})

func unregister_conditional_effects(card: Card) -> void:
	var granted_total: int = 0
	for effect in _conditional_effects:
		if effect["source"] == card:
			granted_total += int(effect.get("granted", 0))
	_conditional_effects = _conditional_effects.filter(func(e): return e["source"] != card)
	if granted_total != 0:
		card.power -= granted_total
		card.current_conditional_bonus = maxi(0, card.current_conditional_bonus - granted_total)
		if card.power_label:
			card.power_label.changePower(card.power)

## CONTINUOUS, COUNT-BASED POWER. "For each point of damage you have received, +1000" (Dark Knight 92, Gabranth 98)
## and "for each Forward your opponent controls, +1000" (Jecht 15).
##
## Same ledger idea as conditional_power: remember what each rule currently GRANTS and apply only the difference, so
## temporary buffs and auras living in `power` are never recomputed away. The count itself is read live from the board
## — there is no counter to keep in sync — so the only duty is to recompute when a count can change: a card entering
## or leaving the field, and a player taking damage.
##
##   "power_per": {"count": {"is_type": "Forward", "controller": "opponent"}, "value": 1000}
##   "power_per": {"count": "damage_received", "value": 1000, "brave_at": 6}
##
## `brave_at` is optional: once the count reaches it, the card gains Brave (status, one turn, refreshed by the same
## recompute), and loses it if the count drops back below.
var _power_per_effects: Array = []

func register_power_per(card: Card) -> void:
	if not ("power_per" in card.card_effects):
		return
	var rules = card.card_effects["power_per"]
	if rules is Dictionary:
		rules = [rules]
	if not (rules is Array):
		return
	for rule in rules:
		if not (rule is Dictionary):
			continue
		_power_per_effects.append({
			"source": card,
			"count": rule.get("count", ""),
			"value": int(rule.get("value", 0)),
			"brave_at": int(rule.get("brave_at", -1)),
			"granted": 0,
			"brave_granted": false,
		})
	recompute_power_per()

func unregister_power_per(card: Card) -> void:
	for rule in _power_per_effects:
		if rule["source"] == card and is_instance_valid(card):
			var granted: int = int(rule["granted"])
			if granted != 0:
				card.power_change(-granted, -1)
	_power_per_effects = _power_per_effects.filter(func(r): return r["source"] != card)

func recompute_power_per() -> void:
	for rule in _power_per_effects:
		var source: Card = rule["source"]
		if source == null or not is_instance_valid(source) or not source.is_on_field():
			continue
		var n: int = _power_per_count(rule["count"], source)
		var desired: int = n * int(rule["value"])
		if desired != int(rule["granted"]):
			source.power_change(desired - int(rule["granted"]), -1)
			rule["granted"] = desired
		var threshold: int = int(rule["brave_at"])
		if threshold > 0:
			var should: bool = n >= threshold
			# Only touch the status the RULE granted: a printed Brave lives in card_effects and must not be erased
			# here, and neither should a status some other effect put there.
			if should != bool(rule["brave_granted"]):
				if should:
					source.add_status_effect("brave", 1)
				else:
					source.status_effects.erase("brave")
				rule["brave_granted"] = should

## How many things a power_per rule counts. "damage_received" is the cards in its controller's damage zone; anything
## else is a criteria block counted against the board.
func _power_per_count(counter, source: Card) -> int:
	if counter is String and counter == "damage_received":
		# Untyped on purpose, so the call can be NAMED: a Node-typed variable cannot call side_for(), and
		# call("side_for", ...) would hide the dependency from both grep and Find Usages.
		var game = get_parent()
		if game == null or not game.has_method("side_for"):
			return 0
		var side = game.side_for(1 if source.controller == "player" else 2)
		return side.damage_count() if side != null else 0
	if counter is Dictionary:
		var total: int = 0
		for card in get_all_cards():
			if card.matches_criteria(counter, source):
				total += 1
		return total
	return 0

func recompute_conditional_power() -> void:
	for effect in _conditional_effects:
		var source: Card = effect["source"]
		if source == null or not is_instance_valid(source) or not source.is_inside_tree():
			continue
		var desired: int = int(effect["value"]) if _condition_met(effect["condition"], source) else 0
		var granted: int = int(effect.get("granted", 0))
		if desired != granted:
			var delta: int = desired - granted
			source.power += delta
			effect["granted"] = desired
			# current_conditional_bonus remains the SUM across this card's rules, for cleanup and diagnostics;
			# the per-rule `granted` above is what prevents two rules from undoing each other.
			source.current_conditional_bonus += delta
			if source.power_label:
				source.power_label.changePower(source.power)

## Is the condition true FOR THIS SOURCE CARD? The source is the card that owns the conditional ("if you control
## Aerith" belongs to Zack), because "you" means its controller — without it the criteria would be read literally
## against a fixed seat, which is the bug that made an AI-owned card check the human's board.
func _condition_met(condition: Dictionary, source: Card = null) -> bool:
	if condition.is_empty():
		return false
	for card in get_all_cards():
		if card.matches_criteria(condition, source):
			return true
	return false

## AURAS — continuous effects a card grants to OTHERS while it is on the field ("your Fire Forwards gain +1000 power",
## card 1-030R). Not the same thing as `conditional_power`, which a card applies to ITSELF when a condition holds.
##
## THE SYSTEM WAS ALREADY HERE AND WAS SIMPLY NEVER CALLED. `AuraValue`, `add_aura`, `activate_aura_in_field`,
## `add_aura_to_card`, `add_all_auras_to_card`, and `Card.does_card_match_target()` — which reads exactly the
## {type, controller, element} block the JSON uses — were all present and correct. Nothing invoked any of them, so
## 1-030R's effect was loaded, stored, and changed no number at all. That is the whole bug.
##
## So this is the WIRING, not a second implementation. Two entry points, one per direction:
##
##   * a card ARRIVES: it receives every aura already on the field, and if it has an aura of its own, that one is
##     registered and applied to everything already there;
##   * a card LEAVES: its auras are removed, and whatever they granted is taken back off the cards they matched.
##
## The accounting is one-shot per (aura, card) pair — applied when the card arrives or when the aura arrives, never
## recomputed in a loop — because that is the shape the existing helpers have, and re-applying in a loop is how a total
## like this ratchets upward every time the field changes.
func register_card_auras(card: Card) -> void:
	# ALREADY REGISTERED IS NOT AN ERROR. This runs both when a card is parented into the field (Card._executeAuraEffects)
	# and when it is played (play_card). Registering twice would create a SECOND AuraValue for the same effect, and since
	# each one keeps its own `granted` record the guard inside add_aura_to_card() would NOT deduplicate them — the bonus
	# would be applied twice. One aura per card per effect, and this is what makes that true.
	for id in _auras:
		if _auras[id].source == card:
			return
	# ADD THE AURA AND ACTIVATE IT, one id per aura. Keyed by the card's instance id, a card granting two things kept only
	# the second — the first was overwritten in the dictionary before anything applied it.
	if "aura" in card.card_effects:
		for effect in card.card_effects["aura"]:
			activate_aura_in_field(add_aura(effect, card))
	add_all_auras_to_card(card)
	refresh_auras()

## EVERY aura onto EVERY card, on every field change. This looks redundant next to the two calls above and is not: it is
## what makes the result independent of the ORDER things arrive in. Which aura a card picks up depended on whether the
## card was already down when the aura arrived (activate_aura_in_field) or arrived afterwards
## (add_all_auras_to_card), and a card that was on the field before the aura could miss out entirely.
##
## It is safe to run repeatedly only because AuraValue.granted makes add_aura_to_card() a no-op for a card it has already
## been applied to — without that guard this would stack a fresh +1000 on every field change.
func refresh_auras() -> void:
	for aura in _auras.values():
		for card in get_all_cards():
			add_aura_to_card(aura, card)

func unregister_card_auras(card: Card) -> void:
	# EVERY aura this card granted — not the single entry a key-per-card dictionary could hold.
	var keys: Array = []
	for id in _auras:
		if _auras[id].source == card:
			keys.append(id)
	for id in keys:
		var aura: AuraValue = _auras[id]
		_auras.erase(id)
		# The exact inverse, off the record of what was actually granted — not off the target test, which would also take the
		# bonus off cards that never received it.
		for other in aura.granted.keys():
			if not is_instance_valid(other):
				continue
			if aura.method == "power_change":
				other.power_change(-aura.value, -1)
			elif aura.method == "grant_status" and not aura.status.is_empty():
				other.revoke_status(aura.status)
		aura.granted.clear()
	
func get_breakable_cards():
	# Forwards whose accumulated damage is equal to or greater than their
	# current power. A card at 0 power is handled separately (it is put into
	# the Graveyard, not broken).
	var ans = []
	for card in (front_cards + opponent_front_cards):
		if card.has_zero_power():
			continue
		if card.is_broken():
			ans.append(card)
	return ans

func get_zero_power_cards():
	# Forwards whose current power is 0 or less. These are put into the
	# Graveyard without triggering break effects.
	var ans = []
	for card in (front_cards + opponent_front_cards):
		if card.has_zero_power():
			ans.append(card)
	return ans

func _tap_selected_cards():
	for c in selected_cards_for_mana_conversion:
		c.tap()
		
## THE ATTACKING PARTY, always including `attacker_card` as its first member. A party of one is just a normal attack,
## so every consumer can keep reading `attacker_card` and only the combat maths has to look here.
##
## Formation rule (from the rules): clicking another Forward while one is already selected JOINS THE PARTY if it is
## the same element; a different element does nothing. There is no "replace the attacker" any more — deselect first.
var attacking_party: Array[Card] = []

func set_attacker(card:Card):
	if card == null:
		return
	if attacker_card == null:
		attacker_card = card
		attacker_card.set_attacker_status(true)
		attacking_party.clear()
		attacking_party.append(card)
	elif attacker_card == card:
		# Clicking the primary again clears the whole formation.
		reset_attacker()
		attacker_changed.emit()
		return
	elif attacking_party.has(card):
		# A non-primary member: clicking it again drops it from the party.
		remove_party_member(card)
		return
	elif add_party_member(card):
		pass
	# else: different element or cannot attack — DO NOTHING, per the party rules.
	attacker_changed.emit()

## Join `card` to the current attack. Returns false when the rules say it cannot: it must be able to attack, it must
## not already be in the party, and it must share the primary's ELEMENT SET (identical, so a mono-element Forward
## cannot join a multi-element one).
func add_party_member(card: Card) -> bool:
	if attacker_card == null or card == null:
		return false
	if card == attacker_card or attacking_party.has(card):
		return false
	if not card.can_attack():
		return false
	if not same_element_as_primary(card):
		return false
	attacking_party.append(card)
	card.set_attacker_status(true)
	print("[Party] %s joins %s (%d members)" % [card.card_name, attacker_card.card_name, attacking_party.size()])
	return true

func remove_party_member(card: Card) -> void:
	if card == null or card == attacker_card or not attacking_party.has(card):
		return
	attacking_party.erase(card)
	if is_instance_valid(card):
		card.set_attacker_status(false)
	print("[Party] %s leaves (%d members)" % [card.card_name, attacking_party.size()])

func same_element_as_primary(card: Card) -> bool:
	if attacker_card == null:
		return false
	return element_set(card) == element_set(attacker_card)

## `element` is an Array on some cards and a bare String on others, so normalise before comparing.
func element_set(card: Card) -> Array:
	var raw = card.element
	var out: Array = raw if raw is Array else [raw]
	out.sort()
	return out

func is_party() -> bool:
	return attacking_party.size() >= 2

## The members of the current attack. FALLS BACK to the lone `attacker_card`: callers (and probes) have always been
## able to set that field directly, and a single attacker is a party of one — it must not need formation to fight.
func party_members() -> Array[Card]:
	if attacking_party.is_empty() and attacker_card != null:
		var one: Array[Card] = [attacker_card]
		return one
	return attacking_party

## Sum of the members' CURRENT power — read at the moment of damage, like a single attacker's power is.
func party_power() -> int:
	var total: int = 0
	for card in party_members():
		if card != null and is_instance_valid(card) and card.is_on_field():
			total += card.power
	return total

## "If ALL members of a Party have Pre-emptive Strike, then the Party has it. Otherwise it does not."
func party_has_first_strike() -> bool:
	var members: Array[Card] = party_members()
	if members.is_empty():
		return false
	for card in members:
		if card == null or not is_instance_valid(card) or not card.is_first_strike():
			return false
	return true

## Drop members that have left the field; a party of fewer than two disbands.
##
## The REMAINING member keeps attacking as a normal single attack — the rules disband the party, not the attack — so
## `attacker_card` is moved to it rather than the whole combat being cancelled.
func prune_party() -> void:
	if attacking_party.is_empty():
		return
	var alive: Array[Card] = []
	for card in attacking_party:
		if card != null and is_instance_valid(card) and card.is_on_field():
			alive.append(card)
		elif card != null and is_instance_valid(card):
			card.set_attacker_status(false)
	attacking_party = alive
	_disband_if_too_small()

## A card is leaving the field. Drop it WITHOUT asking `is_on_field()`: remove_card() runs before the zone actually
## changes (the pile sets it), so a field check there still says FIELD and the "departed" member stayed in the party.
func drop_party_member(card: Card) -> void:
	if card == null or not attacking_party.has(card):
		return
	attacking_party.erase(card)
	if is_instance_valid(card):
		card.set_attacker_status(false)
	_disband_if_too_small()

func _disband_if_too_small() -> void:
	if attacking_party.size() >= 2:
		return
	print("[Party] disbands (%d member(s) left)" % attacking_party.size())
	if attacking_party.is_empty():
		attacker_card = null
	elif not attacking_party.has(attacker_card):
		attacker_card = attacking_party[0]

func reset_attacker():
	# Clear the markers on EVERY member, not just the primary, or a disbanded party leaves "attacking" rings behind.
	for card in attacking_party:
		if card != null and is_instance_valid(card) and card.is_on_field():
			card.set_attacker_status(false)
	attacking_party.clear()
	attacker_card = null

## Select/deselect a blocker for the current combat (human input only).
## Game.set_blocker() is what *declares* it (via the set_blocker instruction).
func set_blocker_card(card: Card) -> void:
	if card == null or card.controller != "player" or not card.can_attack():
		return
	if blocker_card == card:
		card.set_blocker_status(false)
		card.set_selected_highlight(false)
		blocker_card = null
		hide_block_arc()
	else:
		if blocker_card != null and is_instance_valid(blocker_card):
			blocker_card.set_blocker_status(false)
			blocker_card.set_selected_highlight(false)
		blocker_card = card
		card.set_blocker_status(true)
		# Same vocabulary as targeting: blue = legal, orange = the one you picked. So a
		# reselect before committing simply moves the orange and the arc.
		card.set_selected_highlight(true)
		show_block_arc(card)
	blocker_changed.emit()

## Mark every card that could legally block for `controller` with the prompt glow.
##
## Only ever called for the LOCAL defender: the ring means "the game is asking YOU to
## choose". An opponent's declaration shows the arc alone, because that cue is not a
## question addressed to the human.
func set_blockable(controller: String, enabled: bool) -> void:
	for card in get_all_cards():
		if card.controller != controller:
			continue
		card.set_valid_target(enabled and can_block(card))

## The block predicate, and THE ONE PLACE blocking legality is decided. Everything that glows and everything that is
## clickable goes through here, which is what keeps those two in agreement.
##
## "block_disabled" is a status the card data has always handed out — Red Mage's ability applies it — and NOTHING ever
## consulted it, so the ability looked like it worked and did nothing. It belongs here rather than at each call site, for
## the same reason `unbreakable` lives in one place in Game.
##
## The status expires on its own: Card.turn_end() decrements it, so "this turn" is enforced by construction and there is
## no second place that has to remember to take it off.
## "The Backups you control cannot be broken by your opponent's Summons or abilities" (Auron).
##
## A CONTINUOUS rule, asked at the moment of the break — no per-card statuses. That matters because the protected set
## changes: a Backup that arrives later is covered with no refresh, and one that leaves needs no cleanup. The cost is
## that whoever asks must know the cause, which is why damage records its source on the card.
##
## Data on the protector:
##   "protects": {"targets": {"is_type": "Backup", "controller": "player"},
##                "from": "opponent", "by": ["Summon", "Ability"]}
## `targets` is read from the PROTECTOR's perspective, and `by` may be omitted to mean any effect.
##
## GRANTED CHOICE PROTECTION — "The Card Name Sazh you control cannot be chosen by your opponent's Summons or
## abilities" (Dajh). Same continuous shape as the break rule, but asked from the TARGETING gate only: a set effect
## ("all the Backups") still hits the card, because it was never chosen.
##
##   "shields": {"targets": {"is_named": "Sazh"}, "from": "opponent", "by": ["Summon", "Ability"]}
## The rules that read the board live in scripts/rules.gd, owned by this node as `rules`. These forwarders keep the
## Field API stable for every existing caller and probe, so moving a rule out is a one-line change here.
func effective_cost(card: Card) -> Dictionary:
	return rules.effective_cost(card)

func is_protected_from_being_chosen(card: Card, source: Card, source_kind: String) -> bool:
	return rules.is_protected_from_being_chosen(card, source, source_kind)

func is_protected_from_break(card: Card, source_controller: String, source_kind: String) -> bool:
	return rules.is_protected_from_break(card, source_controller, source_kind)

func modify_damage(source: Card, target: Card, amount: int, source_kind: String = "", source_controller: String = "") -> int:
	return rules.modify_damage(source, target, amount, source_kind, source_controller)

## THE ONE PLACE DAMAGE LANDS. Effect damage, combat, party damage and first-strike steps all come through here, so
## "when this card deals damage to a Forward, ..." riders are applied at the same moment on every path rather than
## being re-implemented per call site.
func cause_damage(target: Card, amount: int, source: Card = null, source_kind: String = "", source_controller: String = "") -> int:
	if target == null or not is_instance_valid(target) or amount <= 0:
		return 0
	if source != null and not is_instance_valid(source):
		source = null
	var dealt: int = modify_damage(source, target, amount, source_kind, source_controller)
	target.suffer_damage(dealt, source_kind, source_controller, source)
	if source != null and dealt > 0 and target.is_on_field() and target.type == "Forward":
		_apply_damage_caused_riders(source, target)
	return dealt

## "When the Forward that took damage from Cid Highwind is put from the field into the Break Zone on the same turn, ..."
## (Cid 72/73).
##
## The rider is stored ON THE DAMAGED CARD, not on Cid: a one-turn status carrying the trigger that must run if THAT
## Forward leaves the field. That is what makes it survive Cid leaving play, and carrying the CONTROLLER with it is
## what sends the mill to the right player. `Card.turn_end()` expires it like any other status.
func _apply_damage_caused_riders(source: Card, target: Card) -> void:
	var rules = source.card_effects.get("on_causing_damage_to_forward", [])
	if rules is Dictionary:
		rules = [rules]
	if not (rules is Array):
		return
	for rule in rules:
		if not (rule is Dictionary):
			continue
		var status: String = str(rule.get("status", ""))
		if status.is_empty():
			continue
		var payload: Dictionary = {"duration": int(rule.get("duration", 1)), "controller": source.controller}
		if rule.has("on_enter_break_zone"):
			payload["on_enter_break_zone"] = rule["on_enter_break_zone"]
		print("[Damage] %s marks %s (%s)" % [source.card_name, target.card_name, status])
		target.add_status_effect(status, payload)

func can_block(card: Card) -> bool:
	if card == null:
		return false
	if card.status_effects.has("block_disabled"):
		return false
	if not card.can_attack():
		return false
	if attacker_card == null:
		return true
	# AT LEAST ONE MEMBER, NOT ALL OF THEM. Advanced Rules 15.1.1.9.6: a Forward can block a party if it can legally
	# block at least ONE Forward that makes it up, and that blocks the whole party. For a single attacker this is just
	# "that attacker", so the same loop covers both.
	#
	# (The tempting inverse — "illegal if any member refuses this blocker" — is wrong: a party of two Yuffies with
	# "cannot be blocked by cost 3+ / 4+" is blockable by a cost-3 Forward, because it can block the cost-4 one.)
	var members: Array = party_members()
	if members.is_empty():
		members = [attacker_card]
	for member in members:
		if member == null or not is_instance_valid(member):
			continue
		if not member.allows_blocker(card):
			continue
		if not card.can_block_attacker(member):
			continue
		return true
	return false

## The review link: the arc that shows what a card IN THE STACK was pointed at, re-drawn on
## demand as the player moves over the stack (see Stack.refresh_target_display).
##
## It is drawn by the FIELD, not by the stack, because `BallisticArrow` treats the points it is
## handed as LOCAL coordinates. The stack node is flipped and sits above the board, so an arrow
## parented to it and given global points lands wherever that transform carries it — which is
## exactly what "arrows in random places" was. The Field's frame is identity, as it is for the
## other two arrows, so global points are correct here.
var review_arrow: BallisticArrow = null

func show_review_link(source: Card, target: Card) -> void:
	if source == null or target == null:
		hide_review_link()
		return
	if not is_instance_valid(source) or not is_instance_valid(target):
		hide_review_link()
		return
	if review_arrow == null or not is_instance_valid(review_arrow):
		review_arrow = ballistic_arrow_scene.instantiate()
		add_child(review_arrow)
	# Same convention as the live targeting arrow — from the source's top edge to the target's
	# centre — so a link being reviewed looks exactly like the one that was drawn.
	review_arrow.set_is_aiming(true, source.get_global_top_centre())
	review_arrow.lock_arc(target.get_global_face_centre())

func hide_review_link() -> void:
	if review_arrow != null and is_instance_valid(review_arrow):
		review_arrow.set_is_aiming(false)

## The link from the blocker to the attacker, drawn CENTRE to CENTRE.
##
## Static by design: both cards are already on the field and neither moves while the
## declaration is open, so this aims once and locks. That is the opposite of the targeting
## arrow, which follows the mouse and a card that may still be tweening into the stack.
## ONE ARC PER PARTY MEMBER. When the attacker is a party, the block is not a single link: the blocker's power is
## being divided across every member, so each of them gets an arc from the blocker's face centre. A party of one (the
## ordinary attack) still produces exactly one arc, so this is the same call for both cases.
##
## Static by design: both cards are already on the field and neither moves while the declaration is open, so each arc
## aims once and locks.
func show_block_arc(blocker: Card) -> void:
	hide_block_arc()
	if blocker == null or attacker_card == null:
		return
	var targets: Array = party_members()
	if targets.is_empty():
		targets = [attacker_card]
	for member in targets:
		if member == null or not is_instance_valid(member):
			continue
		var arc: BallisticArrow = ballistic_arrow_scene.instantiate()
		add_child(arc)
		# Adjacent cards are the common case for a block, and the default floor exists to
		# stop a dot being drawn for a near-zero targeting drag.
		arc.min_distance = 0.15
		# A block joins the two battle rows, so its chord runs up the screen. Bowing along
		# screen-up would put the arch along the chord (a 1.54 m path for an 0.85 m span);
		# perpendicular instead makes it a sideways link. Kept shallow — this is a link
		# between two cards, not a shot.
		arc.bow_perpendicular = true
		arc.peak_ratio = 0.22
		arc.set_is_aiming(true, blocker.get_global_face_centre())
		arc.lock_arc(member.get_global_face_centre())
		block_arrows.append(arc)

func hide_block_arc() -> void:
	for arc in block_arrows:
		if arc != null and is_instance_valid(arc):
			arc.set_is_aiming(false)
			arc.queue_free()
	block_arrows.clear()

func reset_blocker():
	# The blocker may have broken in the clash, so only clear the marker while it
	# is still a card on the field.
	if blocker_card != null and is_instance_valid(blocker_card):
		if blocker_card.is_on_field():
			blocker_card.set_blocker_status(false)
		blocker_card.set_selected_highlight(false)
	blocker_card = null
	hide_block_arc()
func _on_assistant_charge_cancelled() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	selected_cards_for_mana_conversion = []


func _on_assistant_charge_complete() -> void:
	if stack.skill_mana_deferred_until_target_confirm or stack.summon_mana_deferred_until_target_confirm:
		return
	for c in selected_cards_for_mana_conversion:
		c.reset()
	_tap_selected_cards()
	selected_cards_for_mana_conversion = []

func apply_deferred_skill_mana_payment() -> void:
	for c in selected_cards_for_mana_conversion:
		c.reset()
	_tap_selected_cards()
	selected_cards_for_mana_conversion = []


func _on_assistant_target_cancel() -> void:
	if stack.skill_mana_deferred_until_target_confirm or stack.summon_mana_deferred_until_target_confirm:
		for c in selected_cards_for_mana_conversion:
			c.reset()
		selected_cards_for_mana_conversion.clear()
	targeting_allow_cancel = false
	target_card = null
	source_card = null
	# EVERY arc, for the same reason as the completion path: a multi-target session leaves one locked on each pick.
	_clear_target_arrows()
	reset_targets()
	# NOTE: the TARGET modal is popped by Assistant.on_target_cancel() /
	# on_target_complete(), which owns the modal it opened. Don't pop here too.


## "WHEN CHOSEN" — called when a targeting session is CONFIRMED, not when rings are clicked.
##
## Only the OPPONENT'S choice counts: Kuja's text says "chosen by ... your opponent", so being picked by its own
## controller must not trigger it. And only Summon/Ability targeting: a set effect reaches cards without choosing them.
## Fired once per session (`_chosen_notified`), because a pick can be replaced before confirming.
func notify_targets_chosen() -> void:
	if _chosen_notified:
		return
	_chosen_notified = true
	if source_card == null or targeting_picked.is_empty():
		return
	var chooser: String = source_card.controller
	var kind: String = targeting_source_kind
	if kind != "Summon" and kind != "Ability":
		return
	for card in targeting_picked:
		if card == null or not is_instance_valid(card):
			continue
		if card.controller == chooser:
			continue
		if not card.is_key_word_in_card_effect("when_chosen"):
			continue
		print("[Chosen] %s was chosen by the opponent's %s" % [card.card_name, kind])
		execute_card_effect(card, "when_chosen")

func _on_stack_execute_card_effect(card: Card) -> void:
	# Targeting session is over: clear all targeting state so the next
	# session starts fresh.
	# EVERY arc, not just the aiming one. A multi-target session leaves a locked arc on each pick, and freeing only
	# `arrow` left the rest of them in the scene pointing at nothing.
	_clear_target_arrows()
	target_card = null
	source_card = null
	targeting_allow_cancel = false
	reset_targets()

## Free every arc this session spawned: the aiming one and the locked ones. Called wherever a session ends.
func _clear_target_arrows() -> void:
	for a in targeting_arrows:
		if a != null and is_instance_valid(a):
			a.queue_free()
	targeting_arrows.clear()
	if arrow != null and is_instance_valid(arrow):
		arrow.queue_free()
	arrow = null

## End a targeting session from the EFFECT side. The normal stack path does this in
## _on_stack_execute_card_effect; event triggers resolve through Game._resolve_event_trigger and need the same
## cleanup afterwards, or the last locked arc and the orange pick ring outlive the effect.
func finish_targeting_state() -> void:
	_clear_target_arrows()
	target_card = null
	source_card = null
	targeting_allow_cancel = false
	reset_targets()
