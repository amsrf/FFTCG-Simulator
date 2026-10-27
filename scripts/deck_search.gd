extends CanvasLayer
class_name DeckSearch
## The deck search window: a card effect (Agrias 1-151R) asks the player to find a card in their deck.
##
## Laid out after a reference (references/search.png): a centred TITLE and SUBTITLE over a fanned row of the
## candidate cards. Three things follow from that reference and are why this is shaped the way it is:
##   * the row is STRONGLY overlapped, like a hand, not spread out;
##   * each card rotates about its BOTTOM edge, not its centre — a fan held in a hand pivots at the bottom, and
##     rotating about the centre makes the cards look laid out on a line instead;
##   * the row is centred in the window, because there is nothing beside it.
##
## A large preview panel used to sit on the right. It is gone: the HOVERED CARD is the zoom now, growing toward the
## viewer in place. Two zooms of the same card was one too many, and the hovered one is the card the player is
## actually looking at.
##
## Only cards that PASS the filter are shown. An earlier pass showed the whole deck with the rest dimmed, which
## buried the takeable cards among the untakeable ones.
##
## Confirm is DISABLED until something is selected, so "confirm nothing" cannot happen by accident — Cancel is how
## you decline, and it is labelled that way.
##
## Usage, from Game.search_deck():
##     var window: DeckSearch = DECK_SEARCH.instantiate()
##     add_child(window)
##     window.open(deck_ids, filter)
##     var chosen: int = await window.finished

signal finished(chosen_id: int)

const CHOOSE_NONE := -1

## The preferred card size. Scaled down to fit the fan's room when it has to be — see _card_size().
const CARD := Vector2(222, 308)
## The MOST a card may be covered by its neighbour, as a fraction of a card's width. Deep, because this is a held
## fan: past about two thirds the stack stops reading as separate cards.
const MAX_OVERLAP_FRACTION := 0.62
## The LEAST a card may be covered by its neighbour — equivalently, the most two card centres may be apart, as a
## fraction of a card's width.
##
## HALF A CARD, which puts the neighbours' bottom edges about half over each other: touching and clearly a hand, but
## every card still readable. Tighter than this and the row becomes a stack of edges where you cannot tell one card
## from the next, which is what 0.30 produced.
const MAX_GAP_FRACTION := 0.5
## How much the hovered card grows. It grows about its BOTTOM-centre pivot, so its base stays on the fan's arc and
## the rest of the card swells outward and up — which is what reads as the card coming toward the viewer. Because it
## happens in place, no other card moves.
##
## This is the whole zoom now that the preview panel is gone, so it is generous. Everything else that has to make
## room for it — the band's height, the card size, where the row sits vertically — is derived from it below.
const HOVER_SCALE := 1.35
## How long a hover takes. Close to the hand's lift rather than its 0.7 s, which is for a card travelling the length
## of the screen.
const SPREAD_SECONDS := 0.16
## How far the fan bows at the ENDS. The ends sit lowest and the middle highest, because that is the shape of a deck
## fanned in a hand — adding the bow at the middle instead reads as a smile, which is what this did first.
const FAN_BOW := 10.0
## How far the outer cards lean. They lean AWAY from the centre, so the row splays like a held fan.
const FAN_TILT_DEGREES := 4.0
## How tall the band is, as a fraction of the window. Roomy on purpose: it holds a header, a full card, the space
## that card needs to grow into when hovered, and the controls underneath.
const BAND_FRACTION := 0.58
## Cards shown at once. The pager only appears when there are more than this — a search usually turns up a handful,
## and a pager that is always there but never needed is just noise.
const PAGE_SIZE := 10
const EDGE_MARGIN := 40.0
const HEADER_HEIGHT := 92.0
const FOOTER_HEIGHT := 60.0

## Loaded by PATH rather than referenced through its class_name: a class_name added since Godot last scanned the
## project is not in the global cache, which is a parse error on every headless run.
const CARD_VIEW := preload("res://scripts/card_view.gd")
## Same reason as CARD_VIEW: preload by path, not the global class cache.
const CARD_FILTER := preload("res://scripts/card_filter.gd")

var selected_id: int = CHOOSE_NONE

## Which card the pointer is over, or -1. The card at this index is the one drawn enlarged and on top.
var _hovered_index: int = -1

## Every card that matched, across all pages. The fan only ever holds one page of them.
var _matching: Array = []
var _page: int = 0

var _fan: Control = null
var _band: Control = null
var _title: Label = null
var _subtitle: Label = null
var _status: Label = null
var _confirm: Button = null
var _cancel: Button = null
var _prev: Button = null
var _next: Button = null
var _page_label: Label = null
## card id -> LIST of the TextureButtons showing it. A LIST because a deck holds duplicates — the test deck has six
## Ovelia — and keyed by a single node per id, most of them would be invisible to selection and to the aura.
var _cards: Dictionary = {}
## The tween currently moving each card, so a new arrangement can cancel the one before it. Keyed by node because the
## fan is laid out per card, and sweeping the pointer along it starts a tween on each in turn.
var _sliding: Dictionary = {}
## The copy the player actually clicked, which is what wears the orange. `selected_id` says WHICH card was chosen for
## the effect; this says which of its copies is lit — different questions when a deck holds duplicates.
var _selected_node: Control = null

func _ready() -> void:
	layer = 10                      # above the board and the match HUD
	_build()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# A dim over the whole screen: the game is paused behind this, and it should look it.
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	_band = ColorRect.new()
	_band.color = Color(0.07, 0.085, 0.12, 0.97)
	root.add_child(_band)
	# Positioned in _layout(), because the band's height is a fraction of the window.

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.modulate = Color(0.93, 0.95, 1.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 16)
	_subtitle.modulate = Color(0.66, 0.72, 0.88)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band.add_child(_subtitle)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.modulate = Color(0.58, 0.63, 0.76)
	_band.add_child(_status)

	# The fan is the only content in the body, so it draws over the band and the status rather than under them.
	_fan = Control.new()
	_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(_fan)

	_prev = Button.new()
	_prev.text = "<"
	_prev.tooltip_text = "Previous cards"
	_prev.pressed.connect(func(): _change_page(-1))
	_band.add_child(_prev)

	_page_label = Label.new()
	_page_label.add_theme_font_size_override("font_size", 14)
	_page_label.modulate = Color(0.66, 0.72, 0.88)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band.add_child(_page_label)

	_next = Button.new()
	_next.text = ">"
	_next.tooltip_text = "More cards"
	_next.pressed.connect(func(): _change_page(1))
	_band.add_child(_next)

	_confirm = Button.new()
	_confirm.text = "Confirm"
	_confirm.disabled = true
	_confirm.pressed.connect(func(): _finish(selected_id))
	_band.add_child(_confirm)

	_cancel = Button.new()
	_cancel.text = "Cancel"
	_cancel.tooltip_text = "Take no card at all"
	_cancel.pressed.connect(func(): _finish(CHOOSE_NONE))
	_band.add_child(_cancel)

	# A CanvasLayer has no `resized` signal; the viewport does.
	get_viewport().size_changed.connect(_layout)
	_layout()

## READ-ONLY VIEW of a zone's cards: the same fan, hover preview and look as the deck search, but nothing to
## choose. Confirm is hidden and Cancel becomes Close, because this asks the player nothing.
##
## Sharing this window rather than writing a second viewer is the point: a card must read the same way wherever it
## is inspected, and two viewers would drift apart within a week.
func open_view(ids: Array, title: String) -> void:
	var shown: Array = []
	for id in ids:
		shown.append(int(id))
	# KEPT IN THE ZONE'S OWN ORDER — slot order is meaningful for damage — rather than sorted like a deck search.
	_matching = shown
	_page = 0
	_title.text = title
	_subtitle.text = "For checking what is in the zone. Nothing is being chosen."
	var count_now: int = shown.size()
	_status.text = "%d card%s. Point at one to read it." % [count_now, "" if count_now == 1 else "s"]
	_rebuild_page()
	_layout()
	# AFTER _layout(), because that is what creates the buttons.
	if _confirm != null:
		_confirm.visible = false
	if _cancel != null:
		_cancel.text = "Close"

## Opens the window on `deck_ids`, showing ONLY the cards that satisfy `filter`.
##
## `subtitle_text` lets the SAME window serve another zone. The Break Zone search (Devout 48/77) is this window; the
## only thing it needs to say differently is where the cards are coming from.
func open(deck_ids: Array, filter: Dictionary, subtitle_text: String = "") -> void:
	var matching: Array = []
	for id in deck_ids:
		if CARD_FILTER.matches(CARD_FILTER.card_by_id(int(id)), filter):
			matching.append(int(id))

	# Sorted by name then id, so copies of one card sit together and the order is stable between openings.
	matching.sort_custom(func(a, b): return _sort_key(a) < _sort_key(b))
	_matching = matching
	_page = 0

	_title.text = "Choose a card"
	_subtitle.text = subtitle_text if subtitle_text != "" else _subtitle_for(filter)

	var takeable: int = matching.size()
	_status.text = "%d card%s to choose from. Point at one to read it." % [
		takeable, "" if takeable == 1 else "s"]

	_rebuild_page()
	_layout()

## Rebuilds the fan for the current page. Called on open and whenever the page changes.
func _rebuild_page() -> void:
	for child in _fan.get_children():
		# remove_child first: queue_free is deferred, so a rebuild in the same frame would still count the old cards
		# through get_children().
		_fan.remove_child(child)
		child.queue_free()
	_cards.clear()
	# Those tweens belonged to nodes that are being freed.
	_sliding.clear()
	selected_id = CHOOSE_NONE
	_selected_node = null
	_hovered_index = -1
	if _confirm != null:
		_confirm.disabled = true

	var first: int = _page * PAGE_SIZE
	var last: int = mini(first + PAGE_SIZE, _matching.size())
	for i in range(first, last):
		_fan.add_child(_make_card(_matching[i]))

func _make_card(id: int) -> Control:
	var button := TextureButton.new()
	# NO custom_minimum_size here. It is a FLOOR, so setting it to CARD would silently clamp away the smaller size
	# _place_cards() assigns — the card stayed 308 px tall while the pivot and the layout maths assumed 283, and the
	# row overflowed its box.
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var art: String = CARD_VIEW.art_path(id)
	if not art.is_empty():
		button.texture_normal = load(art)
	button.material = CARD_VIEW.round_material()
	button.tooltip_text = str(CARD_FILTER.card_by_id(id).get("name_en", "?"))
	button.pressed.connect(func(): _select(id, button))
	button.mouse_entered.connect(func(): _hover(id, button))
	button.mouse_exited.connect(_unhover)
	if not _cards.has(id):
		_cards[id] = []
	_cards[id].append(button)
	return button

## Names then ids, so two copies of the same card keep a stable relative order.
func _sort_key(id: int) -> String:
	var card: Dictionary = CardFilter.card_by_id(id)
	return "%s|%06d" % [str(card.get("name_en", "")).to_lower(), id]

## A sentence describing what the effect is looking for, shown under the title. Built from the filter so it cannot
## drift from what is actually being matched.
func _subtitle_for(filter: Dictionary) -> String:
	var parts: Array = []
	if filter.has("name"):
		parts.append("named \"%s\"" % str(filter["name"]))
	if filter.has("type"):
		parts.append("of type %s" % str(filter["type"]))
	if filter.has("category"):
		parts.append("in category %s" % str(filter["category"]))
	if filter.has("job"):
		parts.append("with job %s" % str(filter["job"]))
	if filter.has("element"):
		parts.append("of element %s" % str(filter["element"]))
	if filter.has("min_power"):
		parts.append("with at least %s power" % str(filter["min_power"]))
	if filter.has("max_power"):
		parts.append("with at most %s power" % str(filter["max_power"]))
	if parts.is_empty():
		return "Search your deck for a matching card."
	return "Search your deck for a card %s." % ", ".join(parts)

## Places the band and the fan. Recomputed on resize rather than laid out once, because the band's height is a
## fraction of the window.
func _layout() -> void:
	if _band == null or _fan == null:
		return
	# A CanvasLayer is not a Control and has no `size` of its own, so the window is asked for its rect.
	var window: Vector2 = _window_size()
	if window.x < 1.0 or window.y < 1.0:
		return

	var band_height: float = maxf(220.0, window.y * BAND_FRACTION)
	_band.position = Vector2(0.0, (window.y - band_height) * 0.5)
	_band.size = Vector2(window.x, band_height)

	# The header is centred across the whole band, so the title sits over the window rather than over the row.
	_title.position = Vector2(EDGE_MARGIN, 14.0)
	_title.size = Vector2(maxf(10.0, window.x - EDGE_MARGIN * 2.0), 32.0)
	_subtitle.position = Vector2(EDGE_MARGIN, 50.0)
	_subtitle.size = Vector2(maxf(10.0, window.x - EDGE_MARGIN * 2.0), 22.0)
	_status.position = Vector2(EDGE_MARGIN, band_height - 44.0)

	var body_top: float = HEADER_HEIGHT
	var body_height: float = maxf(10.0, band_height - HEADER_HEIGHT - FOOTER_HEIGHT)

	# The fan's zone is sized to the ROW rather than to a share of the window, and then centred. A full page has to
	# fit, so the row gives way rather than overflowing the window — and when it does, _place_cards() tightens the
	# step to suit the narrower zone.
	var count: int = _fan.get_child_count()
	var card_size: Vector2 = _card_size_for_height(body_height)
	var row_width: float = card_size.x * (1.0 + float(MAX_GAP_FRACTION) * float(maxi(count - 1, 0)))
	row_width = minf(row_width, maxf(card_size.x, window.x - EDGE_MARGIN * 2.0))
	_fan.position = Vector2(maxf(EDGE_MARGIN, (window.x - row_width) * 0.5), body_top)
	_fan.size = Vector2(maxf(card_size.x, row_width), body_height)

	# Controls: the buttons bottom-right, the pager bottom-centre.
	_cancel.position = Vector2(window.x - EDGE_MARGIN - 110.0, band_height - 52.0)
	_cancel.size = Vector2(110.0, 34.0)
	_confirm.position = Vector2(window.x - EDGE_MARGIN - 226.0, band_height - 52.0)
	_confirm.size = Vector2(100.0, 34.0)

	var pager_visible: bool = _page_count() > 1
	_prev.visible = pager_visible
	_next.visible = pager_visible
	_page_label.visible = pager_visible
	if pager_visible:
		var centre: float = window.x * 0.5
		_prev.position = Vector2(centre - 74.0, band_height - 52.0)
		_prev.size = Vector2(34.0, 34.0)
		_page_label.position = Vector2(centre - 34.0, band_height - 48.0)
		_page_label.size = Vector2(68.0, 26.0)
		_next.position = Vector2(centre + 40.0, band_height - 52.0)
		_next.size = Vector2(34.0, 34.0)
		_page_label.text = "%d / %d" % [_page + 1, _page_count()]
		_prev.disabled = _page <= 0
		_next.disabled = _page >= _page_count() - 1

	# INSTANT: a resize, a new deck, a page turn. Animating here would slide cards in from wherever the previous
	# arrangement left them, which reads as a glitch rather than as motion.
	_place_cards(true)

func _page_count() -> int:
	if _matching.is_empty():
		return 1
	return int(ceil(float(_matching.size()) / float(PAGE_SIZE)))

func _change_page(step: int) -> void:
	var wanted: int = clampi(_page + step, 0, _page_count() - 1)
	if wanted == _page:
		return
	_page = wanted
	# A page turn is a fresh arrangement, so it is instant rather than a slide — the cards on the next page are
	# different cards, not the same ones moving.
	_rebuild_page()
	_layout()

## The card size for a body of `body_height`, fitted to the HEIGHT — and to the space a HOVERED card needs, because
## that card is the largest thing that ever has to fit. The width is the generous axis here and the row's own width
## is derived from this value, so letting a narrow room shrink the card on both axes would only make the row smaller
## than it needs to be.
func _card_size_for_height(body_height: float) -> Vector2:
	# A hovered card grows upward from its base, so the height to reserve is the GROWN one. An outer card also leans
	# about its bottom edge, swinging its top corner up by half a card width times the sine of the lean.
	var needed: float = CARD.y * HOVER_SCALE + FAN_BOW + CARD.x * 0.5 * sin(deg_to_rad(FAN_TILT_DEGREES))
	var fit: float = clampf(body_height / maxf(needed, 1.0), 0.05, 1.0)
	return (CARD * fit).floor()

## The size a card is drawn at: the preferred CARD, shrunk to fit the fan's room when it has to be. Scaled
## proportionally, so the art is never stretched, and never enlarged past CARD.
##
## The height reserved is the GROWN one, matching _card_size_for_height(): a hovered card is the largest thing that
## ever has to fit, and if the two disagreed the row would be placed for one size and drawn at another.
func _card_size() -> Vector2:
	var room: Vector2 = _fan.size
	if room.x < 1.0 or room.y < 1.0:
		return CARD
	# An outer card leans FAN_TILT_DEGREES about its BOTTOM edge, which swings its top corner up by half a card width
	# times the sine of that angle. That is height the row needs on top of the card and the bow.
	var lean: float = CARD.x * 0.5 * sin(deg_to_rad(FAN_TILT_DEGREES))
	var needed: Vector2 = Vector2(CARD.x, CARD.y * HOVER_SCALE + FAN_BOW + lean)
	var fit: float = minf(1.0, minf(room.x / needed.x, room.y / needed.y))
	return (CARD * fit).floor()

## Fans the cards out along a shallow arc.
##
## `instant` is for a FRESH arrangement — a new deck, a resize, a page turn — where animating from wherever the
## previous cards happened to be would read as a glitch. A hover animates, because a row of cards snapping is worse
## than not moving at all.
func _place_cards(instant: bool = false) -> void:
	var count: int = _fan.get_child_count()
	if count == 0:
		return
	var room: Vector2 = _fan.size
	# The size actually drawn, which is CARD unless the room is too small for it — see _card_size().
	var card_size: Vector2 = _card_size()
	# The step starts from the width available, so a row that does not fit tightens. Then it is CLAMPED at BOTH ends
	# to a fraction of a card's width: MAX_OVERLAP_FRACTION is the deepest overlap allowed, MAX_GAP_FRACTION the
	# shallowest. The clamp is what keeps the row a tightly packed FAN instead of spreading to fill the room.
	var step: float = (room.x - card_size.x) / float(maxi(count - 1, 1))
	step = clampf(step, -card_size.x * MAX_OVERLAP_FRACTION, card_size.x * MAX_GAP_FRACTION)
	# The zone is exactly as wide as the row, so the row starts at its left edge and is centred by _layout().
	var left: float = 0.0
	var middle: float = float(count - 1) * 0.5
	# The row is centred vertically, but never so high that a hovered card would grow out of the top of the box, and
	# never so low that the resting cards fall out of the bottom. Those two limits are what the band's height and
	# _card_size_for_height() are sized against.
	var growth: float = (HOVER_SCALE - 1.0) * card_size.y
	var centred: float = (room.y - card_size.y - FAN_BOW) * 0.5
	var top: float = clampf(centred, growth, maxf(growth, room.y - FAN_BOW - card_size.y))

	for i in range(count):
		var card: Control = _fan.get_child(i)
		var lateral: float = float(i) - middle
		# Normalised to -1..1 across the fan, so the bow and the tilt are the same shape whatever the count is.
		var t: float = 0.0 if middle <= 0.0 else lateral / middle
		# The bow is added at the ENDS, so the middle sits highest — a fanned deck curves up at the centre.
		var bow: float = t * t * FAN_BOW
		# The hovered card LIFTS TOWARD THE VIEWER rather than the row making room for it. Growing it about its
		# bottom-centre pivot leaves its base where it is while the rest of the card swells outward and up, which is
		# what reads as coming closer. Nudging the neighbours aside only ever read as the whole row shuffling
		# sideways, and it moved cards the player was not pointing at.
		var zoom: float = HOVER_SCALE if i == _hovered_index else 1.0
		# Drawn OVER its neighbours: a card coming towards the viewer must not pass behind the next one, which would
		# undo the illusion. z_index rather than move_to_front(), because that would renumber the fan indexes that
		# _hovered_index is expressed in.
		card.z_index = 1 if i == _hovered_index else 0
		# POSITIVE for a card at the right-hand end: a card leans AWAY from the centre of the fan, so the right cards
		# tip clockwise and the left ones anti-clockwise. `t` is negative on the left, so `+t` gives that — the same
		# sign the hand's fan uses. It was negated here, which made the fan lean into itself.
		var tilt: float = t * FAN_TILT_DEGREES
		card.size = card_size
		# PIVOT AT THE BOTTOM EDGE, not the centre. A fan is held at the bottom, so the cards splay from there;
		# rotating about the centre instead swings them around the middle and reads as cards lying on a line. The
		# pivot is also what a hover grows about, so the base stays put and the card swells upward.
		card.pivot_offset = Vector2(card_size.x * 0.5, card_size.y)
		_move_card(card, Vector2(left + float(i) * step, top + bow), tilt, zoom, instant)

## Puts one card where the fan says it goes: instantly for a fresh arrangement, tweened for a hover. Any tween
## already running on that card is killed first, because sweeping the pointer along the row starts one per card and
## they would otherwise fight over the same properties.
func _move_card(card: Control, target: Vector2, tilt_degrees: float, zoom: float, instant: bool) -> void:
	var running: Tween = _sliding.get(card)
	if running != null and running.is_valid():
		running.kill()
	_sliding.erase(card)
	var target_scale := Vector2(zoom, zoom)
	if instant or not card.is_inside_tree():
		card.position = target
		card.rotation_degrees = tilt_degrees
		card.scale = target_scale
		return
	var tween: Tween = card.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", target, SPREAD_SECONDS)
	tween.parallel().tween_property(card, "rotation_degrees", tilt_degrees, SPREAD_SECONDS)
	tween.parallel().tween_property(card, "scale", target_scale, SPREAD_SECONDS)
	_sliding[card] = tween

## The database id of the card a node is showing, or CHOOSE_NONE.
func _id_of(node: Control) -> int:
	if node == null:
		return CHOOSE_NONE
	for id in _cards:
		for candidate in _cards[id]:
			if candidate == node:
				return int(id)
	return CHOOSE_NONE

## `node` is the COPY the player actually touched. A deck holds duplicates, so the id alone does not say which copy
## should light up: `selected_id` records the choice for the effect, and `_selected_node` records which copy is
## wearing the orange.
func _select(id: int, node: Control) -> void:
	# Clicking the card that is ALREADY selected de-selects it, which is how you change your mind. Confirm goes back
	# to disabled, so "nothing chosen" stays the honest state — Cancel remains the way to leave with none.
	if _selected_node == node:
		CARD_VIEW.set_aura(node, false, CARD_VIEW.HOVER_COLOUR)
		_selected_node = null
		selected_id = CHOOSE_NONE
		if _confirm != null:
			_confirm.disabled = true
		_status.text = "Nothing chosen. Cancel to take no card."
		return
	# The old selection goes back to blue before the new one turns orange, so exactly one card is ever orange.
	if _selected_node != null and is_instance_valid(_selected_node):
		CARD_VIEW.set_aura(_selected_node, false, CARD_VIEW.HOVER_COLOUR)
	selected_id = id
	_selected_node = node
	CARD_VIEW.set_aura(node, true, CARD_VIEW.SELECTED_COLOUR)
	if _confirm != null:
		_confirm.disabled = false
	_status.text = "Chosen: %s" % str(CARD_FILTER.card_by_id(id).get("name_en", "?"))

func _hover(_id: int, node: Control) -> void:
	if node == null:
		return
	if node != _selected_node:
		CARD_VIEW.set_aura(node, true, CARD_VIEW.HOVER_COLOUR)
	# Remember which card is under the pointer: it is the one that grows, and nothing else moves.
	_hovered_index = node.get_index()
	_place_cards()

func _unhover() -> void:
	for id in _cards:
		for node in _cards[id]:
			if node != _selected_node:
				CARD_VIEW.set_aura(node, false, CARD_VIEW.HOVER_COLOUR)
	# ...and the row settles back, with nothing left enlarged.
	_hovered_index = -1
	_place_cards()

## The visible window rect. A CanvasLayer is not a Control and has no `size` of its own, so every layout question
## goes through here rather than through `size`.
func _window_size() -> Vector2:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2.ZERO
	return viewport.get_visible_rect().size

func _finish(chosen_id: int) -> void:
	finished.emit(chosen_id)
	queue_free()
