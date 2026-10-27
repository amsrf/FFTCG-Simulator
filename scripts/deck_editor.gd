extends Control
## Deck editor.
##
## THE POOL IS THUMBNAILS, NOT TEXT, and that is not only a style choice: card names are CJK and the
## project's UI font does not carry those glyphs, so a text list would render as blanks. The art at
## `assets/cards/<code>.jpg` is already there for every card, so the grid is honest and legible
## without a font. Names appear as tooltips, which are worth having even when they cannot be drawn.
##
## ONLY ONE PAGE IS BUILT AT A TIME. The database is 3644 cards; instancing a thumbnail per card and
## letting Godot `load()` 3644 JPEGs would take seconds and hundreds of megabytes. The grid is
## rebuilt on every filter/page change and touches only what is on screen.
##
## THE DECK HAS TWO VIEWS (see references/editor2.png). The LIST is a column of rows on the right;
## the CARDS view is a full-width strip along the bottom showing one stacked pile per distinct card
## with an xN badge. They are alternatives, not both at once: the list needs the right column and the
## strip needs the full width, so each view hides the other.

const CARD_DATABASE := "res://assets/card_database.json"
const ART_DIR := "res://assets/cards/"
## FF TCG deck rules — the numbers the counter is measured against.
const DECK_SIZE := 50
const MAX_COPIES := 3
## Thumbnails per page, and the gutter between them. Matched to references/editor.png: SIX across and
## TWO rows (~12 cards), with a clear gap so each card reads as a separate object rather than a sheet.
const COLUMNS := 6
const ROWS := 2
const PAGE_SIZE := COLUMNS * ROWS
const CELL_GAP := 14
const THUMB_SIZE := Vector2(190, 264)
## The hover preview: a card big enough to read its rules text from, placed beside the card it belongs to.
const PREVIEW_SIZE := Vector2(363, 508)
const PREVIEW_GAP := 14.0
## It grows into place rather than appearing: a card popping into existence reads as a glitch.
const PREVIEW_GROW_FROM := 0.1
const PREVIEW_GROW_SECONDS := 0.14
## Corner rounding for card art. In UV, so it is a fraction of the image rather than pixels.
const THUMB_RADIUS := 0.07
const ROUND_SHADER := preload("res://shaders/thumb_round.gdshader")
## The deck strip: how tall it is, how big its cards are, and how far each stacked copy is offset.
## TWO heights, because a 50-card deck at the compact height still needs scrolling — the expand handle
## lets the strip take over most of the window when you actually want to read the deck.
const STRIP_HEIGHT_COMPACT := 212
const STRIP_HEIGHT_EXPANDED := 430
const STRIP_CARD := Vector2(124, 174)
const STACK_SHIFT := 7
## Where decks are written. `user://` rather than `res://` because a deck is the player's, not the
## project's — and it must work from an exported build, where res:// is read-only.
const DECK_DIR := "user://decks"

## Element symbols as the database stores them, paired with the English name to show and the colour
## that stands for them. The database keys elements by the CJK character, which the UI font cannot
## draw, so anything that reaches a Label has to be translated first: MATCH on `key`, DISPLAY `label`.
##
## The colours are a COPY of Card.ELEMENT_COLOURS, not a reference to it: a `class_name` is not in
## Godot's global class cache until the editor rescans it, so naming Card here would break a headless
## run of the editor. If the palette changes in one place it must change in the other.
const ELEMENTS := [
	{"key": "火", "label": "Fire", "colour": Color(0.86, 0.09, 0.17)},
	{"key": "氷", "label": "Ice", "colour": Color(0.55, 0.87, 0.98)},
	{"key": "風", "label": "Wind", "colour": Color(0.36, 0.85, 0.44)},
	{"key": "土", "label": "Earth", "colour": Color(0.90, 0.74, 0.26)},
	{"key": "雷", "label": "Lightning", "colour": Color(0.72, 0.45, 1.00)},
	{"key": "水", "label": "Water", "colour": Color(0.32, 0.58, 1.00)},
	{"key": "光", "label": "Light", "colour": Color(1.00, 0.95, 0.78)},
	{"key": "闇", "label": "Dark", "colour": Color(0.58, 0.52, 0.86)},
]

## The element of a card as a colour, for the stripe on its deck row. Falls back to a neutral grey for
## a card with no element rather than to some arbitrary hue.
func element_colour_of(id: int) -> Color:
	var value: Variant = card_at(id).get("element")
	var wanted: String = ""
	if value is Array:
		wanted = str(value[0]) if value.size() > 0 else ""
	else:
		wanted = str(value)
	for entry in ELEMENTS:
		if entry["key"] == wanted:
			return entry["colour"]
	return Color(0.45, 0.47, 0.52)

## Bounds taken from the database rather than guessed: power runs 0..10000 in steps of 1000 (0 is a
## Backup, which has no power), cost runs 0..11. Stepping power by 1 would give 10000 useless notches.
const POWER_STEP := 1000
const POWER_MAX := 10000
const COST_MAX := 11

var cards: Array = []
var filtered: Array[int] = []
var deck: Array[int] = []
var page: int = 0
var deck_name: String = "default"
## The card that represents this deck in the picker. 0 = none chosen, and the picker falls back to the
## deck's first card — so choosing a face is a nicety, never a requirement.
var face_id: int = 0

## Chooses the deck's face, or clears it back to the default when `id` is 0. Kept here rather than in the
## click handler so the picker's own logic has one entry point.
func set_face(id: int) -> void:
	face_id = id
	_toggle_face_picking(false)
	_set_status("Face: %s" % (name_of(id) if id > 0 else "first card of the deck"))

## Arms or disarms face picking. While armed the next pool click sets the face — see _on_pool_pressed.
func _toggle_face_picking(on: bool) -> void:
	_picking_face = on
	_set_face_ui()

func _set_face_ui() -> void:
	if _face_button == null:
		return
	if _picking_face:
		_face_button.text = "Face: pick a card…"
	else:
		_face_button.text = "Face: %s" % (name_of(face_id) if face_id > 0 else "auto")

## A pool thumbnail's click currently means "add this card"; face picking borrows it. The button says which
## meaning is live, because a mode you cannot see is a mode you forget you are in.
var _picking_face: bool = false
var _face_button: Button = null
var _name_box: LineEdit = null
## The name this deck was OPENED under, which stops being the same as `deck_name` the moment it is renamed.
## save_deck() renames FROM this, so changing the name moves the file instead of leaving the old one behind
## and creating what looks like a second deck.
var _loaded_from: String = ""
## The two deck views are INDEPENDENT: either, both or neither can be on. The list wants the right column
## and the strip wants full width, but the layout gives each what it asks for rather than trading one for
## the other, so the decklist and the card piles can be read at the same time.
##
## BOTH START ON, because the card strip is the view that actually shows you the deck — the list is a
## summary of the same thing, and hiding it by default made the editor open on the less useful half.
var deck_list_visible: bool = true
var deck_cards_visible: bool = true

var _search: LineEdit = null
var _grid: GridContainer = null
var _deck_rows: VBoxContainer = null
var _count_label: Label = null
var _page_label: Label = null
var _status: Label = null
var _type_filter: OptionButton = null
var _element_filter: OptionButton = null
var _title_filter: OptionButton = null
var _job_filter: LineEdit = null
var _power_min: SpinBox = null
var _power_max: SpinBox = null
var _cost_min: SpinBox = null
var _cost_max: SpinBox = null
## The right-hand column, hidden when the cards view is on (the pool takes its width).
var _deck_panel: Control = null
## The bottom strip and its scroll holder.
var _deck_strip: HBoxContainer = null
var _deck_strip_holder: Control = null
## The two view toggles. Independent, because the list and the card strip can both be up.
var _list_button: Button = null
var _cards_button: Button = null
## The preview's grow tween. Killed before a new one starts, so a fast pointer cannot leave the card
## stranded part-way between 0.1 and full size.
var _preview_tween: Tween = null
## The big hover copy of a card. A sibling of the whole UI rather than a child of it, so it draws on top.
var _preview: TextureRect = null
## The expand/collapse handle on the boundary between the pool and the strip.
var _strip_toggle: Button = null
## Whether the strip has been expanded to take most of the window.
var _strip_expanded: bool = false

## Grows the strip and squeezes the pool, or the reverse. Only reachable while the strip is on screen:
## the handle's visibility follows the strip (see _set_deck_cards_visible), so there is nothing else to expand.
func _set_strip_expanded(expanded: bool) -> void:
	_strip_expanded = expanded
	if _deck_strip_holder != null:
		_deck_strip_holder.custom_minimum_size = Vector2(0,
			STRIP_HEIGHT_EXPANDED if expanded else STRIP_HEIGHT_COMPACT)
	if _strip_toggle != null:
		_strip_toggle.text = "▼  Collapse deck" if expanded else "▲  Expand deck"

func _ready() -> void:
	# WHICH deck we are editing: the picker leaves the choice on MatchSetup, because a scene cannot be handed
	# an argument. An empty name is a NEW deck — it starts blank under a placeholder name that will not
	# collide with a real file until it is saved.
	var opening: String = MatchSetup.editing_deck_name
	deck_name = "new deck" if opening.is_empty() else opening
	# The file this deck came from. Empty for a NEW deck, which is what tells save_deck() there is nothing to
	# rename on the first save.
	_loaded_from = opening
	_load_database()
	_build_ui()
	if not opening.is_empty():
		load_deck()
	_apply_filter()

# --- data ------------------------------------------------------------------

func _load_database() -> void:
	var file := FileAccess.open(CARD_DATABASE, FileAccess.READ)
	if file == null:
		push_error("[DeckEditor] cannot open %s" % CARD_DATABASE)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or not parsed.has("cards"):
		push_error("[DeckEditor] %s is not a card database" % CARD_DATABASE)
		return
	cards = parsed["cards"]
	print("[DeckEditor] loaded %d cards" % cards.size())

## Card id is 1-based (index + 1), matching CardDatabase's convention.
func card_at(id: int) -> Dictionary:
	var index: int = id - 1
	if index < 0 or index >= cards.size():
		return {}
	return cards[index]

func code_of(id: int) -> String:
	return str(card_at(id).get("code", ""))

func name_of(id: int) -> String:
	return str(card_at(id).get("name_en", "?"))

func type_of(id: int) -> String:
	return str(card_at(id).get("type_en", "?"))

func cost_of(id: int) -> int:
	var value: Variant = card_at(id).get("cost", 0)
	return int(value) if value != null else 0

## Card art path for an id, or "" when there is no art on disk.
func art_of(id: int) -> String:
	var code: String = code_of(id)
	if code.is_empty():
		return ""
	var path: String = ART_DIR + code + ".jpg"
	return path if ResourceLoader.exists(path) else ""

# --- filter + page ---------------------------------------------------------

func _apply_filter() -> void:
	filtered.clear()
	for i in range(cards.size()):
		if _matches(cards[i]):
			filtered.append(i + 1)
	page = 0
	_rebuild_pool()

## ONE predicate for every control. Keeping them in a single place is what stops the controls drifting
## apart in meaning — and it is the only thing a new filter has to be added to.
func _matches(card: Dictionary) -> bool:
	var needle: String = _search.text.strip_edges().to_lower()
	if not needle.is_empty():
		var code: String = str(card.get("code", "")).to_lower()
		var name_en: String = str(card.get("name_en", "")).to_lower()
		if not (needle in code or needle in name_en):
			return false
	var type_pick: String = _picked(_type_filter)
	if not type_pick.is_empty() and str(card.get("type_en", "")) != type_pick:
		return false
	# The card's element is a LIST, and any one of them matching is enough.
	if _element_filter.get_selected_id() > 0:
		if not _has_element(card, ELEMENTS[_element_filter.get_selected_id() - 1]["key"]):
			return false
	# Job is "contains", not equality: there are 522 distinct jobs, so a dropdown would be unusable.
	var job: String = _job_filter.text.strip_edges().to_lower()
	if not job.is_empty() and not (job in str(card.get("job_en", "")).to_lower()):
		return false
	# category_1 is the Final Fantasy title the card is from (Roman numerals: VII, XIV, …).
	var title_pick: String = _picked(_title_filter)
	if not title_pick.is_empty() and str(card.get("category_1", "")) != title_pick:
		return false
	var power: int = int(str(card.get("power", "0")))
	if power < int(_power_min.value) or power > int(_power_max.value):
		return false
	var cost: int = int(str(card.get("cost", "0")))
	if cost < int(_cost_min.value) or cost > int(_cost_max.value):
		return false
	return true

## The text of the selected entry, or "" for the "Any" entry at index 0 — so a zero selection always
## means "no filter" and the predicate never has to special-case a missing value.
func _picked(option: OptionButton) -> String:
	if option == null or option.get_selected_id() <= 0:
		return ""
	return str(option.get_item_text(option.get_selected_id()))

func _has_element(card: Dictionary, wanted: String) -> bool:
	var value: Variant = card.get("element")
	if value is Array:
		return wanted in value
	return str(value) == wanted

## A dropdown whose index 0 is an "Any" entry, so a zero selection means "no filter".
func _make_dropdown(parent: Control, any_label: String, values: Array) -> OptionButton:
	var option := OptionButton.new()
	option.add_item(any_label)
	for value in values:
		option.add_item(str(value))
	option.item_selected.connect(func(_i: int): _apply_filter())
	parent.add_child(option)
	return option

func _make_spin(parent: Control, label_text: String, max_value: int, step: float, initial: int) -> SpinBox:
	var column := VBoxContainer.new()
	var caption := Label.new()
	caption.text = label_text
	caption.add_theme_font_size_override("font_size", 11)
	caption.modulate = Color(0.7, 0.75, 0.9)
	column.add_child(caption)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = max_value
	spin.step = step
	spin.value = initial
	spin.custom_minimum_size = Vector2(104, 0)
	spin.value_changed.connect(func(_v: float): _apply_filter())
	column.add_child(spin)
	parent.add_child(column)
	return spin

## The database's own distinct type_en values, sorted — so a new card type shows up in the UI without
## anyone remembering to add it here.
func _type_values() -> Array:
	var seen: Dictionary = {}
	for card in cards:
		var value: String = str(card.get("type_en", ""))
		if not value.is_empty():
			seen[value] = true
	var out: Array = seen.keys()
	out.sort()
	return out

func _element_labels() -> Array:
	var out: Array = []
	for entry in ELEMENTS:
		out.append(entry["label"])
	return out

## Same idea for category_1, which turns out to be the FF title the card is from.
func _title_values() -> Array:
	var seen: Dictionary = {}
	for card in cards:
		var value: String = str(card.get("category_1", ""))
		if not value.is_empty():
			seen[value] = true
	var out: Array = seen.keys()
	out.sort()
	return out

func _reset_filters() -> void:
	_search.text = ""
	_type_filter.selected = 0
	_element_filter.selected = 0
	_title_filter.selected = 0
	_job_filter.text = ""
	_power_min.value = 0
	_power_max.value = POWER_MAX
	_cost_min.value = 0
	_cost_max.value = COST_MAX
	_apply_filter()

func page_count() -> int:
	return maxi(1, int(ceil(float(filtered.size()) / float(PAGE_SIZE))))

func _rebuild_pool() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var start: int = page * PAGE_SIZE
	var end: int = mini(start + PAGE_SIZE, filtered.size())
	for i in range(start, end):
		_grid.add_child(_make_pool_button(filtered[i]))
	_page_label.text = "Page %d / %d  (%d cards)" % [page + 1, page_count(), filtered.size()]

## Shows a big copy of `id` beside `box`, the rect of the card it belongs to. The art files ARE the whole
## card, rules text included, so enlarging the art is exactly what "read its effect" needs.
##
## TO THE RIGHT, or the LEFT when there is no room: a preview that hangs off the window is worse than
## none, and one that covers the card you are pointing at is worse still. The vertical is centred on that
## card and clamped the same way.
func _show_preview(id: int, box: Rect2) -> void:
	if _preview == null:
		return
	var art: String = art_of(id)
	if art.is_empty():
		_hide_preview()
		return
	_preview.texture = load(art)

	var room: Vector2 = size
	var x: float = box.position.x + box.size.x + PREVIEW_GAP
	if x + PREVIEW_SIZE.x > room.x:
		x = box.position.x - PREVIEW_GAP - PREVIEW_SIZE.x
	x = clampf(x, 0.0, maxf(0.0, room.x - PREVIEW_SIZE.x))
	# Centred on the card it belongs to, but pushed UP when that would run off the bottom: a card near the
	# bottom of the window has no room below it, and plain clamping there would leave the preview hanging
	# off the edge. Centring first and only then shifting keeps the common case centred.
	var y: float = box.position.y + box.size.y * 0.5 - PREVIEW_SIZE.y * 0.5
	if y + PREVIEW_SIZE.y > room.y:
		y = room.y - PREVIEW_SIZE.y
	y = clampf(y, 0.0, maxf(0.0, room.y - PREVIEW_SIZE.y))
	_preview.position = Vector2(x, y)

	# Grown from its centre, so the growth reads as the card swelling rather than sliding in.
	_preview.pivot_offset = PREVIEW_SIZE * 0.5
	_preview.scale = Vector2.ONE * PREVIEW_GROW_FROM
	_preview.visible = true
	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
	_preview_tween = create_tween()
	_preview_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_preview_tween.tween_property(_preview, "scale", Vector2.ONE, PREVIEW_GROW_SECONDS)

func _hide_preview() -> void:
	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
	if _preview != null:
		_preview.visible = false

## A material that cuts a texture's corners round. Built per call rather than shared: a shared material
## would be mutated by whichever caller touched it last, and card art needs a longer radius than a
## thumbnail does anyway.
func _round_material(radius: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ROUND_SHADER
	mat.set_shader_parameter("radius", radius)
	return mat

## Everything a hover does, in one call: light the card's own border blue and show or hide its zoom card.
## They are one interaction, so keeping them together stops a caller doing only half of it.
##
## `node` supplies the RECT and, unless `aura` is given, is also the surface that lights up. The strip piles
## need the split: the hover and the click are caught by an invisible button covering the whole pile, but the
## thing that should glow is the front card image underneath it.
##
## The aura is TWEENED rather than switched, so the border fades up instead of blinking on. The material is
## per-card (see _round_material), which is what makes that safe — a shared material would light every card.
func _hover_card(node: Control, id: int, on: bool, aura: Control = null) -> void:
	var aura_node: Control = aura if aura != null else node
	if aura_node != null and aura_node.material is ShaderMaterial:
		var card_material: ShaderMaterial = aura_node.material
		var from: float = 0.0
		var current: Variant = card_material.get_shader_parameter("hover")
		# A missing parameter reads back as null, and float(null) is a hard error rather than a 0.
		if current is float:
			from = current
		var tween := create_tween()
		tween.tween_method(func(v: float): material.set_shader_parameter("hover", v),
			from, 1.0 if on else 0.0, 0.12)
	if on:
		_show_preview(id, Rect2(node.global_position - global_position, node.size))
	else:
		_hide_preview()

func _make_pool_button(id: int) -> Control:
	var button := TextureButton.new()
	button.custom_minimum_size = THUMB_SIZE
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	# Rounded corners: the art is a rectangle, and a card does not read as a card without them.
	button.material = _round_material(THUMB_RADIUS)
	var art: String = art_of(id)
	if not art.is_empty():
		button.texture_normal = load(art)
	button.tooltip_text = "%s  %s  cost %d" % [name_of(id), code_of(id), cost_of(id)]
	button.pressed.connect(_on_pool_pressed.bind(id))
	button.mouse_entered.connect(func(): _hover_card(button, id, true))
	button.mouse_exited.connect(func(): _hover_card(button, id, false))
	return button

func _on_pool_pressed(id: int) -> void:
	# In face-picking mode a click CHOOSES THE FACE instead of adding a card. Routing it here rather than
	# giving the pool a second button means the two actions cannot drift apart, and it costs one branch.
	if _picking_face:
		set_face(id)
		return
	if deck.size() >= DECK_SIZE:
		_set_status("Deck is full (%d)" % DECK_SIZE)
		return
	if _copies_of(id) >= MAX_COPIES:
		_set_status("Already %d copies — the limit is %d" % [MAX_COPIES, MAX_COPIES])
		return
	deck.append(id)
	_refresh_deck()

# --- the deck --------------------------------------------------------------

func _copies_of(id: int) -> int:
	var total: int = 0
	for entry in deck:
		if entry == id:
			total += 1
	return total

## Unique ids, in the order they were added, so the panel reads like a decklist.
func deck_summary() -> Array:
	var counts: Dictionary = {}
	var order: Array[int] = []
	for id in deck:
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] += 1
	var out: Array = []
	for id in order:
		out.append({"id": id, "count": counts[id]})
	return out

## Both deck views are rebuilt together. They show the same data, so leaving one stale would mean the
## toggle could display a deck that no longer exists.
func _refresh_deck() -> void:
	for child in _deck_rows.get_children():
		child.queue_free()
	for entry in deck_summary():
		_deck_rows.add_child(_make_deck_row(entry["id"], entry["count"]))
	_count_label.text = "%d / %d cards" % [deck.size(), DECK_SIZE]
	_count_label.modulate = Color(1, 0.85, 0.4) if deck.size() == DECK_SIZE else Color(0.8, 0.85, 1.0)
	_rebuild_deck_strip()

## One deck row, matched to references/editor.png: a coloured element stripe, then the NAME, the cost
## and the quantity. The thumbnail is gone on purpose — at this row height a 36 px card art is
## unreadable, and the reference puts the card's identity in the text instead.
func _make_deck_row(id: int, count: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.tooltip_text = "%s  %s" % [name_of(id), code_of(id)]
	# Hovering a deck row zooms the card, the same as a pool thumbnail. Labels ignore the mouse by
	# default, so the row receives the hover across its whole width; the remove button does not, which is
	# correct — pointing at the button should not be what opens the card.
	row.mouse_entered.connect(func(): _hover_card(row, id, true))
	row.mouse_exited.connect(func(): _hover_card(row, id, false))

	# The element stripe: full row height, narrow. It reads as a colour CODE rather than a swatch.
	var stripe := ColorRect.new()
	stripe.color = element_colour_of(id)
	stripe.custom_minimum_size = Vector2(6, 30)
	row.add_child(stripe)

	var label := Label.new()
	label.text = name_of(id)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.custom_minimum_size = Vector2(130, 0)
	row.add_child(label)

	# Cost, tinted so the number reads as "mana cost" at a glance rather than as another word.
	var cost := Label.new()
	cost.text = str(cost_of(id))
	cost.custom_minimum_size = Vector2(26, 0)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.modulate = Color(0.72, 0.80, 1.0)
	row.add_child(cost)

	var qty := Label.new()
	qty.text = "x%d" % count
	qty.custom_minimum_size = Vector2(28, 0)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(qty)

	var minus := Button.new()
	minus.text = "-"
	minus.tooltip_text = "Remove one copy"
	minus.pressed.connect(_on_deck_remove.bind(id))
	row.add_child(minus)
	return row

## The card view of the deck: one stacked pile per distinct card, with an xN badge when it is >1.
func _rebuild_deck_strip() -> void:
	if _deck_strip == null:
		return
	for child in _deck_strip.get_children():
		child.queue_free()
	for entry in deck_summary():
		_deck_strip.add_child(_make_strip_entry(entry["id"], entry["count"]))

## One pile. The copies are drawn back-to-front with a small offset, each one dimmer than the one in
## front, so the pile's own thickness shows the count and the badge states it. Clicking removes a copy.
func _make_strip_entry(id: int, count: int) -> Control:
	# Room for the offset plus the badge, so the last pile is not clipped by the scroll container.
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(STRIP_CARD.x + STACK_SHIFT * (count - 1) + 18,
		STRIP_CARD.y + STACK_SHIFT * (count - 1) + 18)
	cell.tooltip_text = "%s  %s  —  x%d (click to remove one)" % [name_of(id), code_of(id), count]

	var art: String = art_of(id)
	var depth: int = maxi(count, 1)
	# The FRONT card image, which is the one the hover aura lights — assigned in the loop below, because it
	# is built back-to-front so the front ends up drawn last.
	var front_thumb: TextureRect = null
	for i in range(depth - 1, -1, -1):
		if art.is_empty():
			# No art on disk: a plain plate still shows the stack depth and the badge.
			var plate := ColorRect.new()
			plate.color = element_colour_of(id)
			plate.size = STRIP_CARD
			plate.position = Vector2(i * STACK_SHIFT, i * STACK_SHIFT)
			cell.add_child(plate)
			continue
		var thumb := TextureRect.new()
		thumb.texture = load(art)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		thumb.size = STRIP_CARD
		thumb.position = Vector2(i * STACK_SHIFT, i * STACK_SHIFT)
		# Back copies dimmed, so "which one is the front card" is never in doubt.
		thumb.modulate = Color(1, 1, 1) if i == 0 else Color(0.55, 0.58, 0.66)
		# Rounded corners and the hover aura, like any other card image. Only the FRONT copy takes the
		# material: the ones behind it are dimmed plates and should not light up.
		if i == 0:
			thumb.material = _round_material(THUMB_RADIUS)
			front_thumb = thumb
		cell.add_child(thumb)

	if count > 1:
		var badge := Label.new()
		badge.text = "x%d" % count
		badge.add_theme_font_size_override("font_size", 16)
		badge.add_theme_color_override("font_color", Color(1, 0.92, 0.45))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		badge.add_theme_constant_override("outline_size", 5)
		# TOP-right, not bottom-right: the bottom of a card is where the frame and the card's own stats
		# sit, so a badge there competes with them. The top corner is empty.
		badge.position = Vector2(STRIP_CARD.x - 46 + STACK_SHIFT * (count - 1), 4)
		cell.add_child(badge)

	var hit := Button.new()
	hit.flat = true
	hit.size = cell.custom_minimum_size
	hit.tooltip_text = "Remove one copy of %s" % name_of(id)
	hit.pressed.connect(_on_deck_remove.bind(id))
	# The hit button covers the whole pile, so it catches the hover and the click — but the RECT comes from
	# the CELL, which includes the stack offset, and the AURA goes on the front card image beneath it.
	hit.mouse_entered.connect(func(): _hover_card(hit, id, true, front_thumb))
	hit.mouse_exited.connect(func(): _hover_card(hit, id, false, front_thumb))
	cell.add_child(hit)
	return cell

func _on_deck_remove(id: int) -> void:
	var index: int = deck.rfind(id)
	if index == -1:
		return
	deck.remove_at(index)
	_refresh_deck()

## The two deck views are INDEPENDENT of each other — no longer alternatives. The layout copes with both at
## once: the pool simply gives up the width the list needs and the height the strip needs.
func _set_deck_list_visible(on: bool) -> void:
	deck_list_visible = on
	if _deck_panel != null:
		_deck_panel.visible = on
	if _list_button != null:
		_list_button.text = "List: On" if on else "List: Off"

func _set_deck_cards_visible(on: bool) -> void:
	deck_cards_visible = on
	if _deck_strip_holder != null:
		_deck_strip_holder.visible = on
	# The expand handle sits on the boundary the strip owns, so it lives and dies with it.
	if _strip_toggle != null:
		_strip_toggle.visible = on
	if _cards_button != null:
		_cards_button.text = "Cards: On" if on else "Cards: Off"
	if on:
		_rebuild_deck_strip()

		_refresh_deck()

# --- persistence -----------------------------------------------------------

## Decks are JSON so they stay readable and diffable, and so a deck can be written by hand.
func deck_path(deck_key: String = "") -> String:
	var which: String = deck_name if deck_key.is_empty() else deck_key
	return "%s/%s.json" % [DECK_DIR, which]

func save_deck(deck_key: String = "") -> bool:
	DirAccess.make_dir_recursive_absolute(DECK_DIR)
	var target: String = deck_name if deck_key.is_empty() else deck_key
	var path: String = deck_path(target)

	# RENAMING MOVES THE FILE. Without this, changing the name wrote a SECOND file and left the first one
	# behind — which looks exactly like the editor having created a new deck.
	if not _loaded_from.is_empty() and _loaded_from != target:
		var old_path: String = deck_path(_loaded_from)
		# Refuse rather than silently destroy a different deck that already has the name being moved onto.
		if FileAccess.file_exists(path):
			_set_status("%s already exists — pick another name" % target)
			return false
		if FileAccess.file_exists(old_path):
			var dir := DirAccess.open(DECK_DIR)
			if dir == null or dir.rename(_loaded_from + ".json", target + ".json") != OK:
				_set_status("Could not rename %s to %s" % [_loaded_from, target])
				return false

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Could not write %s" % path)
		return false
	file.store_string(JSON.stringify({
		"name": target,
		"cards": deck,
		# The picker's tile art. Written even when 0, so the file documents the field rather than leaving its
		# absence ambiguous.
		"face": face_id,
	}, "\t"))
	file.close()
	# From here on this deck IS the file it was just written to, whatever it used to be called.
	_loaded_from = target
	_set_status("Saved %d cards to %s" % [deck.size(), path])
	return true

func load_deck(deck_key: String = "") -> bool:
	var path: String = deck_path(deck_key)
	if not FileAccess.file_exists(path):
		_set_status("No deck at %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary) or not parsed.has("cards"):
		_set_status("%s is not a deck file" % path)
		return false
	# The name this deck was READ from — taken from the PATH, not from inside the file, which may have been
	# hand-edited. It is what a later rename moves, so it must be captured before `deck_name` is overwritten.
	_loaded_from = path.get_file().get_basename()
	# Name and face come back too, so reopening a deck looks the same as when it was saved — otherwise the
	# picker's tile would lose its face until the deck were saved again.
	deck_name = str(parsed.get("name", deck_name))
	face_id = int(parsed.get("face", 0))
	if _name_box != null:
		_name_box.text = deck_name
	_set_face_ui()
	deck.clear()
	for entry in parsed["cards"]:
		deck.append(int(entry))
	_refresh_deck()
	_set_status("Loaded %d cards from %s" % [deck.size(), path])
	return true

# --- ui --------------------------------------------------------------------

func _set_status(text: String) -> void:
	_status.text = text

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	add_child(root)

	# --- top bar
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)

	var title := Label.new()
	title.text = "Deck Editor"
	title.add_theme_font_size_override("font_size", 26)
	top.add_child(title)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 20)
	top.add_child(_count_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	# Two independent toggles rather than one either/or switch: the decklist and the card piles are useful
	# together, and the layout can serve both. Their labels name the STATE, because they do not exclude each
	# other — "View: List" would imply that pressing it takes the list away.
	_list_button = Button.new()
	_list_button.tooltip_text = "Show or hide the decklist column"
	_list_button.pressed.connect(func(): _set_deck_list_visible(not deck_list_visible))
	top.add_child(_list_button)

	_cards_button = Button.new()
	_cards_button.tooltip_text = "Show or hide the deck as stacked card images"
	_cards_button.pressed.connect(func(): _set_deck_cards_visible(not deck_cards_visible))
	top.add_child(_cards_button)

	# Held on the editor rather than kept local, because load_deck() has to put the saved name back into it.
	_name_box = LineEdit.new()
	_name_box.text = deck_name
	_name_box.custom_minimum_size = Vector2(160, 0)
	_name_box.tooltip_text = "Deck name — the file is user://decks/<name>.json"
	_name_box.text_changed.connect(func(text: String): deck_name = text)
	top.add_child(_name_box)

	# Label the face button now, so its state is visible before anything has been clicked.
	_set_face_ui()

	# The deck's FACE: the card that represents it in the picker. Pressing this arms the choice — the next
	# pool card clicked becomes the face — because there is no room for a second picker on this screen, and
	# the pool is already a grid of every card in the game.
	_face_button = Button.new()
	_face_button.tooltip_text = "Choose which card represents this deck in the picker"
	_face_button.pressed.connect(func(): _toggle_face_picking(not _picking_face))
	top.add_child(_face_button)

	# Save first, so what you play is what is on screen and what is on disk. The name goes to
	# MatchSetup as well, so the match reads THIS file rather than the default one.
	var play := Button.new()
	play.text = "Play This Deck"
	play.tooltip_text = "Save, then start a match where both players use this deck"
	play.pressed.connect(func():
		save_deck()
		MatchSetup.custom_deck_name = deck_name
		MatchSetup.start_match("custom"))
	top.add_child(play)

	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(func(): save_deck())
	top.add_child(save)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(func(): load_deck())
	top.add_child(load_btn)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): MatchSetup.go_to_menu())
	top.add_child(back)

	# --- body: pool on the left, deck list on the right
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)

	_search = LineEdit.new()
	_search.placeholder_text = "Search by name or code (e.g. Ifrit, 1-004R)"
	_search.text_changed.connect(func(_t: String): _apply_filter())
	left.add_child(_search)

	# Filters, in two rows: identity (type / element / job / title), then numbers (power / cost).
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	left.add_child(row1)

	_type_filter = _make_dropdown(row1, "Any type", _type_values())
	_element_filter = _make_dropdown(row1, "Any element", _element_labels())

	_job_filter = LineEdit.new()
	_job_filter.placeholder_text = "Job contains…"
	_job_filter.custom_minimum_size = Vector2(180, 0)
	_job_filter.tooltip_text = "522 distinct jobs in the database, so this matches part of a name (e.g. Knight)"
	_job_filter.text_changed.connect(func(_t: String): _apply_filter())
	row1.add_child(_job_filter)

	_title_filter = _make_dropdown(row1, "Any title", _title_values())

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	left.add_child(row2)

	_power_min = _make_spin(row2, "Power min", POWER_MAX, POWER_STEP, 0)
	_power_max = _make_spin(row2, "Power max", POWER_MAX, POWER_STEP, POWER_MAX)
	_cost_min = _make_spin(row2, "Cost min", COST_MAX, 1, 0)
	_cost_max = _make_spin(row2, "Cost max", COST_MAX, 1, COST_MAX)

	var reset := Button.new()
	reset.text = "Reset filters"
	reset.tooltip_text = "Clear every filter, including the search box"
	reset.pressed.connect(_reset_filters)
	row2.add_child(reset)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	# The gutter between cards, so the pool reads as separate objects rather than one sheet. The
	# reference has a visible gap on both axes; without it the cards touch and read as a wall.
	_grid.add_theme_constant_override("h_separation", CELL_GAP)
	_grid.add_theme_constant_override("v_separation", CELL_GAP)
	scroll.add_child(_grid)

	var pager := HBoxContainer.new()
	left.add_child(pager)
	var prev := Button.new()
	prev.text = "< Prev"
	prev.pressed.connect(func():
		page = maxi(0, page - 1)
		_rebuild_pool())
	pager.add_child(prev)
	var next := Button.new()
	next.text = "Next >"
	next.pressed.connect(func():
		page = mini(page_count() - 1, page + 1)
		_rebuild_pool())
	pager.add_child(next)
	_page_label = Label.new()
	pager.add_child(_page_label)

	_deck_panel = VBoxContainer.new()
	_deck_panel.custom_minimum_size = Vector2(300, 0)
	body.add_child(_deck_panel)

	var deck_title := Label.new()
	deck_title.text = "Deck"
	deck_title.add_theme_font_size_override("font_size", 20)
	_deck_panel.add_child(deck_title)

	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_deck_panel.add_child(deck_scroll)

	_deck_rows = VBoxContainer.new()
	deck_scroll.add_child(_deck_rows)

	# --- the deck card strip, full width, under the body
	# The expand handle sits HERE, between the pool above and the strip below, because the boundary
	# between them is what it moves: expanding grows the strip and squeezes the pool.
	_strip_toggle = Button.new()
	_strip_toggle.text = "▲  Expand deck"
	_strip_toggle.tooltip_text = "Give the deck strip more room, or hand it back to the card pool"
	_strip_toggle.visible = false
	_strip_toggle.pressed.connect(func():
		_set_strip_expanded(not _strip_expanded))
	root.add_child(_strip_toggle)

	_deck_strip_holder = ScrollContainer.new()
	_deck_strip_holder.custom_minimum_size = Vector2(0, STRIP_HEIGHT_COMPACT)
	_deck_strip_holder.visible = false
	root.add_child(_deck_strip_holder)

	# The hover preview is added to SELF, after root, so it draws over the whole UI. It IGNORES the mouse:
	# one that accepted input would take the hover off the card that spawned it and flicker in and out.
	_preview = TextureRect.new()
	_preview.visible = false
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	# Same corner rounding as the thumbnails, at a longer radius because this card is bigger.
	_preview.material = _round_material(THUMB_RADIUS)
	_preview.size = PREVIEW_SIZE
	_preview.position = Vector2.ZERO
	add_child(_preview)

	_deck_strip = HBoxContainer.new()
	_deck_strip.add_theme_constant_override("separation", 10)
	_deck_strip_holder.add_child(_deck_strip)

	_status = Label.new()
	_status.modulate = Color(0.7, 0.75, 0.9)
	root.add_child(_status)

	# Label the toggles before anything can be clicked, and lay out whatever is showing.
	_set_deck_list_visible(deck_list_visible)
	_set_deck_cards_visible(deck_cards_visible)
	_refresh_deck()
