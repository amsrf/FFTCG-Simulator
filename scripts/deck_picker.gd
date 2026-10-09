extends Control
## The deck picker: choose a deck to edit, or start a new one.
##
## It exists because the editor needs to know WHICH deck it is editing, and a scene cannot be handed an
## argument — so the choice is made here and left on `MatchSetup` for the editor to read. Everything it
## knows about decks comes from `MatchSetup.list_decks()`, the single reader for what is on disk.

const CARD_DIR := "res://assets/cards"

const TILE := Vector2(196, 274)
const TILE_GAP := 18
const COLUMNS := 5

var _tiles: HBoxContainer = null
var _empty_note: Label = null

func _ready() -> void:
	_build()
	_refresh()

func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.07, 0.08, 0.11)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 14)
	root.offset_left = 32
	root.offset_top = 24
	root.offset_right = -32
	root.offset_bottom = -24
	add_child(root)

	var title := Label.new()
	title.text = "Choose a deck"
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)

	var create := Button.new()
	create.text = "Create New Deck"
	create.tooltip_text = "Start a blank deck in the editor"
	create.pressed.connect(_on_create)
	actions.add_child(create)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): MatchSetup.go_to_menu())
	actions.add_child(back)

	_empty_note = Label.new()
	_empty_note.modulate = Color(0.7, 0.75, 0.9)
	root.add_child(_empty_note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", TILE_GAP)
	scroll.add_child(_tiles)

func _refresh() -> void:
	for child in _tiles.get_children():
		# remove_child first: queue_free is deferred, so a rebuild in the same frame would otherwise leave
		# the old tiles counted by get_children() — the bug that doubled the cost row once.
		_tiles.remove_child(child)
		child.queue_free()

	var decks: Array = MatchSetup.list_decks()
	_empty_note.visible = decks.is_empty()
	if decks.is_empty():
		_empty_note.text = "No saved decks yet. Create one to get started."
	for deck in decks:
		_tiles.add_child(_make_tile(deck))

## One deck: its face card, its name, and how many cards are in it. Clicking opens it for editing.
func _make_tile(deck: Dictionary) -> Control:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 6)
	cell.custom_minimum_size = Vector2(TILE.x, TILE.y + 54)

	var art: String = "%s/%s.jpg" % [CARD_DIR, code_of(int(deck["face"]))]
	var button := TextureButton.new()
	button.custom_minimum_size = TILE
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(art):
		button.texture_normal = load(art)
	button.tooltip_text = "Edit %s" % str(deck["name"])
	button.pressed.connect(func(): MatchSetup.go_to_deck_editor(str(deck["name"])))
	cell.add_child(button)

	var label := Label.new()
	label.text = str(deck["name"])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.custom_minimum_size = Vector2(TILE.x, 0)
	cell.add_child(label)

	var count := Label.new()
	count.text = "%d cards" % int(deck["count"])
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.modulate = Color(0.68, 0.72, 0.85)
	cell.add_child(count)

	var remove := Button.new()
	remove.text = "Delete"
	remove.tooltip_text = "Delete this deck"
	remove.pressed.connect(func(): _confirm_delete(str(deck["name"])))
	cell.add_child(remove)

	return cell

## Deleting a deck cannot be undone, so it always goes through a confirmation. The dialog is built on demand
## and frees itself when it closes, so nothing has to keep track of it — and it is parented to the picker
## rather than to the tile, because _refresh() rebuilds every tile underneath it.
func _confirm_delete(deck_name: String) -> void:
	var confirm := ConfirmationDialog.new()
	confirm.title = "Delete deck"
	confirm.dialog_text = "Delete \"%s\"?\n\nThis cannot be undone." % deck_name
	confirm.ok_button_text = "Delete"
	confirm.cancel_button_text = "Keep"
	confirm.confirmed.connect(func(): _delete_deck(deck_name))
	confirm.close_requested.connect(confirm.queue_free)
	confirm.confirmed.connect(confirm.queue_free)
	add_child(confirm)
	confirm.popup_centered()

func _delete_deck(deck_name: String) -> void:
	if MatchSetup.delete_deck(deck_name):
		_refresh()

## The card's printed code, which is how the art files are named. Read straight out of the database array:
## ids are 1-based, so id == index + 1, the same convention every other reader in the project uses.
func code_of(id: int) -> String:
	var db: Array = CardDatabase.card_database
	if id < 1 or id > db.size():
		return ""
	var card: Dictionary = db[id - 1]
	return str(card.get("code", ""))

func _on_create() -> void:
	# An empty name IS "new deck" — see MatchSetup.go_to_deck_editor.
	MatchSetup.go_to_deck_editor("")

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		MatchSetup.go_to_menu()
