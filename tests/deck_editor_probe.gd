extends Node
## Deck editor + custom-deck match probe.
##
## Runs against the REAL scripts: the editor's model, MatchSetup's loader, and
## MatchSetup.build_config("custom"). It uses a deck name of its own ("probe_deck") and removes every
## file it creates afterwards, so a probe run can never touch the deck you saved in the editor.
##
## `extends Node`, not SceneTree: this is a scene (see deck_editor_probe.tscn), and a SceneTree
## script cannot be attached to a node.

const EDITOR := preload("res://scripts/deck_editor.gd")
const PROBE_DECK := "probe_deck"
## A second name the rename checks move the deck to, so the cleanup list can name it too.
const PROBE_RENAMED := "probe_renamed"

var _checks: int = 0
var _failures: int = 0

func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[DeckProbe] FAIL %s" % what)

func _ready() -> void:
	# --- the editor's model ---------------------------------------------------------------
	var editor: Control = EDITOR.new()
	add_child(editor)
	await get_tree().process_frame

	_expect(editor.cards.size() > 3000, "the editor loads the card database (%d cards)" % editor.cards.size())
	_expect(editor.code_of(4) == "1-004C", "card 4 is 1-004C (got %s)" % editor.code_of(4))
	_expect(not editor.art_of(4).is_empty(), "card 4 has art on disk (%s)" % editor.art_of(4))
	_expect(editor.art_of(999999).is_empty(), "a card with no art returns no path")
	_expect(editor.cost_of(4) >= 0, "cost converts from the database's string form")

	# MAX_COPIES is enforced, and so is DECK_SIZE.
	editor.deck.clear()
	for _i in range(editor.MAX_COPIES):
		editor._on_pool_pressed(4)
	_expect(editor.deck.size() == editor.MAX_COPIES, "three copies accepted")
	editor._on_pool_pressed(4)
	_expect(editor.deck.size() == editor.MAX_COPIES, "a fourth copy is refused")
	editor.deck.clear()
	for _i in range(editor.DECK_SIZE + 5):
		editor._on_pool_pressed(4 + (_i % 40))
	_expect(editor.deck.size() == editor.DECK_SIZE, "the deck stops at %d cards" % editor.DECK_SIZE)

	# Summary groups by id and counts copies.
	editor.deck.clear()
	editor._on_pool_pressed(12)
	editor._on_pool_pressed(12)
	editor._on_pool_pressed(41)
	var summary: Array = editor.deck_summary()
	_expect(summary.size() == 2, "summary has one row per distinct card (%d)" % summary.size())
	var copies: int = 0
	for row in summary:
		if row["id"] == 12:
			copies = row["count"]
	_expect(copies == 2, "summary counts two copies of id 12 (got %d)" % copies)

	# The deck row: an element stripe, then name, cost and quantity.
	var row: Control = editor._make_deck_row(4, 2)
	add_child(row)
	await get_tree().process_frame
	var stripe: ColorRect = null
	var texts: Array = []
	for node in row.get_children():
		if node is ColorRect:
			stripe = node
		elif node is Label:
			texts.append((node as Label).text)
	_expect(stripe != null, "the deck row has an element stripe")
	if stripe != null:
		_expect(stripe.color.is_equal_approx(editor.element_colour_of(4)),
			"and it is the card's own element colour")
		_expect(stripe.custom_minimum_size.x < stripe.custom_minimum_size.y,
			"the stripe is taller than it is wide, so it reads as a colour code")
	_expect(editor.name_of(4) in texts, "the row shows the card's NAME (got %s)" % str(texts))
	_expect(str(editor.cost_of(4)) in texts, "the row shows the COST on its own")
	_expect("x2" in texts, "the row shows the QUANTITY")
	row.queue_free()

	# Removing takes one copy at a time.
	editor._on_deck_remove(12)
	_expect(editor.deck.count(12) == 1, "remove takes exactly one copy")

	# The CARD view of the deck: one stacked pile per DISTINCT card, with an xN badge on duplicates.
	editor.deck.clear()
	editor._on_pool_pressed(4)
	editor._on_pool_pressed(4)
	editor._on_pool_pressed(12)
	await get_tree().process_frame
	_expect(editor._deck_strip.get_child_count() == 2,
		"the strip has one pile per distinct card, not per copy (%d)" % editor._deck_strip.get_child_count())
	var badges: Array = []
	for pile in editor._deck_strip.get_children():
		for node in pile.get_children():
			if node is Label:
				badges.append((node as Label).text)
	_expect("x2" in badges, "the duplicated card carries an x2 badge (badges: %s)" % str(badges))
	_expect(not ("x1" in badges), "a single copy gets no badge at all")

	# The two views are INDEPENDENT: either, both or neither. The old either/or switch meant you could not
	# read the decklist and the card piles together, which is the point of having both.
	editor._set_deck_cards_visible(true)
	await get_tree().process_frame
	_expect(editor.deck_cards_visible, "the cards view reports itself as active")
	_expect(editor._deck_strip_holder.visible, "and shows the card strip")
	_expect(editor._deck_panel.visible, "while LEAVING the list up — they are not alternatives")
	_expect(editor._strip_toggle.visible, "and the expand handle comes with the strip")

	editor._set_deck_list_visible(false)
	await get_tree().process_frame
	_expect(not editor._deck_panel.visible, "the list can be hidden on its own")
	_expect(editor._deck_strip_holder.visible, "without disturbing the strip")

	editor._set_deck_cards_visible(false)
	await get_tree().process_frame
	_expect(not editor._deck_strip_holder.visible, "and the strip can be hidden on its own")
	_expect(not editor._strip_toggle.visible, "taking its expand handle with it")

	editor._set_deck_list_visible(true)
	editor._set_deck_cards_visible(true)
	await get_tree().process_frame
	_expect(editor._deck_panel.visible and editor._deck_strip_holder.visible,
		"both at once, which is the whole point of splitting them")

	# The hover preview: big enough to read a card's rules text, and never off the edge of the window.
	# A size is set by hand because the probe node has no layout to inherit one from, and the clamp is
	# computed from the editor's own rect — with a zero-size parent it would pin to the origin and the
	# assertion below would pass for the wrong reason.
	editor.size = Vector2(1200, 800)
	await get_tree().process_frame

	# A card in the middle: the preview goes to its RIGHT, clear of it.
	var card_box := Rect2(Vector2(400, 300), Vector2(190, 264))
	editor._show_preview(4, card_box)
	_expect(editor._preview.visible, "showing a preview makes it visible")
	_expect(editor._preview.texture != null, "and it carries the card's art")
	_expect(editor._preview.position.x >= card_box.position.x + card_box.size.x - 0.5,
		"the preview sits to the RIGHT of the card, not over it (%0.1f vs %0.1f)" % [
			editor._preview.position.x, card_box.position.x + card_box.size.x])
	_expect(editor._preview.scale.x < 1.0, "and starts small, so it grows into place")

	# A card near the right edge: no room on the right, so it flips to the LEFT.
	var edge_box := Rect2(Vector2(editor.size.x - 200, 300), Vector2(190, 264))
	editor._show_preview(4, edge_box)
	_expect(editor._preview.position.x + editor._preview.size.x <= edge_box.position.x + 0.5,
		"with no room on the right the preview flips to the LEFT of the card")
	var corner: Vector2 = editor._preview.position + editor._preview.size
	_expect(corner.x <= editor.size.x + 1.0 and corner.y <= editor.size.y + 1.0,
		"and either way it stays inside the window (%s in %s)" % [str(corner), str(editor.size)])

	# Corner rounding, so the art does not read as a rectangle.
	_expect(editor._preview.material is ShaderMaterial, "the preview is drawn with the rounding shader")

	editor._show_preview(999999, Rect2(Vector2.ZERO, Vector2(190, 264)))
	_expect(not editor._preview.visible, "a card with no art on disk shows no preview at all")
	editor._show_preview(4, card_box)
	_expect(editor._preview.visible, "and showing one again works")
	editor._hide_preview()
	_expect(not editor._preview.visible, "hiding puts it away")
	_expect(editor._preview.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the preview ignores the mouse, or it would steal the hover that opened it")

	# --- filters -----------------------------------------------------------------------------
	# Each filter is checked against a count measured from the database itself, so a filter that
	# silently matches nothing (or everything) fails rather than looking plausible.
	editor._reset_filters()
	_expect(editor.filtered.size() == editor.cards.size(), "no filters = every card (%d)" % editor.filtered.size())

	var type_names: Array = editor._type_values()
	_expect(type_names.size() == 5, "the type list is derived from the data (%d)" % type_names.size())
	_expect("Summon" in type_names, "and contains Summon")
	# +1 because index 0 is the "Any" entry.
	editor._type_filter.selected = type_names.find("Summon") + 1
	editor._apply_filter()
	_expect(editor.filtered.size() == 276, "type=Summon gives 276 (got %d)" % editor.filtered.size())
	var all_summons: bool = true
	for id in editor.filtered:
		if editor.type_of(id) != "Summon":
			all_summons = false
	_expect(all_summons, "every result really is a Summon")

	editor._reset_filters()
	var labels: Array = editor._element_labels()
	_expect(labels.size() == 8, "eight elements (%d)" % labels.size())
	_expect(labels[0] == "Fire" and labels[5] == "Water", "elements are labelled in English (%s)" % str(labels))
	editor._element_filter.selected = labels.find("Fire") + 1
	editor._apply_filter()
	_expect(editor.filtered.size() > 0, "element=Fire matches cards (%d)" % editor.filtered.size())
	var all_fire: bool = true
	for id in editor.filtered:
		if not editor._has_element(editor.card_at(id), "火"):
			all_fire = false
	_expect(all_fire, "and every result really carries the Fire element")
	var unfiltered_total: int = editor.cards.size()
	_expect(editor.filtered.size() < unfiltered_total, "the element filter actually narrows the pool")

	editor._reset_filters()
	editor._job_filter.text = "knight"
	editor._apply_filter()
	var knights: int = editor.filtered.size()
	_expect(knights > 0, "job contains 'knight' matches cards (%d)" % knights)
	_expect(knights > 80, "job matching is case-insensitive and partial (Knight is 80 alone, so >80)")
	var all_knights: bool = true
	for id in editor.filtered:
		if not ("knight" in str(editor.card_at(id).get("job_en", "")).to_lower()):
			all_knights = false
	_expect(all_knights, "and every result's job really contains it")

	editor._reset_filters()
	var titles: Array = editor._title_values()
	_expect(titles.size() == 115, "115 FF titles in category_1 (%d)" % titles.size())
	editor._title_filter.selected = titles.find("VII") + 1
	editor._apply_filter()
	_expect(editor.filtered.size() == 249, "title=VII gives 249 (got %d)" % editor.filtered.size())

	# Power and cost. POWER 0 IS NOT ONLY BACKUPS: 1436 cards have no power — Backups, but also every
	# Summon and Crystal and most Monsters, because a card with no body has no power to have. That is
	# worth knowing here and in the game: it is exactly why the break rule scans front cards only.
	editor._reset_filters()
	editor._power_min.value = 1000
	editor._apply_filter()
	var with_power: int = editor.filtered.size()
	_expect(with_power == 2208, "power>=1000 gives 2208 (got %d)" % with_power)
	var all_positive: bool = true
	for id in editor.filtered:
		if int(str(editor.card_at(id).get("power", "0"))) < 1000:
			all_positive = false
	_expect(all_positive, "and none of the results has less")
	editor._reset_filters()
	editor._power_max.value = 0
	editor._apply_filter()
	var no_power: int = editor.filtered.size()
	_expect(no_power == 1436, "power max 0 is the 1436 cards with no power (got %d)" % no_power)
	_expect(with_power + no_power == editor.cards.size(),
		"and the two halves account for every card (%d + %d)" % [with_power, no_power])

	editor._reset_filters()
	editor._cost_max.value = 1
	editor._apply_filter()
	var cheap: int = editor.filtered.size()
	_expect(cheap > 0 and cheap < editor.cards.size(), "cost<=1 narrows the pool (%d)" % cheap)
	var all_cheap: bool = true
	for id in editor.filtered:
		if editor.cost_of(id) > 1:
			all_cheap = false
	_expect(all_cheap, "and nothing costs more than 1")

	# Two filters combine rather than replacing each other.
	editor._reset_filters()
	editor._cost_max.value = 1
	editor._type_filter.selected = type_names.find("Forward") + 1
	editor._apply_filter()
	_expect(editor.filtered.size() <= cheap, "filters stack — adding a type cannot widen the result")
	var all_forward: bool = true
	for id in editor.filtered:
		if editor.type_of(id) != "Forward" or editor.cost_of(id) > 1:
			all_forward = false
	_expect(all_forward, "and both conditions hold on every result")

	# Reset clears every control, not just most of them.
	editor._reset_filters()
	_expect(editor.filtered.size() == editor.cards.size(), "reset clears every filter (%d)" % editor.filtered.size())
	_expect(editor._search.text.is_empty() and editor._job_filter.text.is_empty(), "including the text boxes")
	_expect(editor._power_max.value == editor.POWER_MAX, "and restores the power ceiling")
	_expect(editor.page == 0, "reset also returns to the first page")

	# --- save, and read it back through MatchSetup ------------------------------------------
	editor.deck.clear()
	for id in [4, 4, 12, 41, 41, 41, 71]:
		editor.deck.append(id)
	var saved: bool = editor.save_deck(PROBE_DECK)
	_expect(saved, "save_deck writes %s" % editor.deck_path(PROBE_DECK))
	_expect(FileAccess.file_exists(editor.deck_path(PROBE_DECK)), "the deck file exists on disk")

	# MatchSetup owns reading a deck; the editor only writes one.
	var ids: Array = MatchSetup.load_deck_ids(PROBE_DECK)
	ids.sort()
	var expected: Array = [4, 4, 12, 41, 41, 41, 71]
	_expect(ids == expected, "MatchSetup reads back the same ids (%s vs %s)" % [str(ids), str(expected)])

	# --- the face, and the picker's reader --------------------------------------------------
	# The face used to be implicit; it is chosen in the editor now and read back by the picker.
	editor.set_face(41)
	_expect(editor.face_id == 41, "choosing a face records it")
	_expect(not editor._picking_face, "and leaves picking mode, so the next click adds a card again")
	_expect(editor.save_deck(PROBE_DECK), "the deck saves with its face")

	# MatchSetup.list_decks() is the ONE reader the picker and anything else share.
	var found: Dictionary = {}
	for entry in MatchSetup.list_decks():
		if str(entry["name"]) == PROBE_DECK:
			found = entry
	_expect(not found.is_empty(), "list_decks() finds the saved deck")
	_expect(int(found.get("face", 0)) == 41, "and reports the face that was chosen")
	_expect(int(found.get("count", 0)) == 7, "and its card count")

	# A deck saved with no face falls back to its FIRST card, so a deck from before faces still shows a tile.
	editor.set_face(0)
	editor.save_deck(PROBE_DECK)
	var fallback: Dictionary = {}
	for entry in MatchSetup.list_decks():
		if str(entry["name"]) == PROBE_DECK:
			fallback = entry
	_expect(int(fallback.get("face", 0)) == editor.deck[0],
		"a deck with no face reports its first card instead (%d)" % int(fallback.get("face", 0)))

	# --- renaming moves the file ------------------------------------------------------------
	# This was a real bug: changing the name and pressing Save wrote a SECOND file and left the first one
	# behind, which looks exactly like the editor having created a new deck.
	editor._loaded_from = PROBE_DECK
	editor.deck_name = PROBE_RENAMED
	_expect(editor.save_deck(), "saving under a new name succeeds")
	_expect(FileAccess.file_exists(editor.deck_path(PROBE_RENAMED)), "the renamed deck is on disk")
	_expect(not FileAccess.file_exists(editor.deck_path(PROBE_DECK)),
		"and the OLD file is gone — a rename is not a copy")
	_expect(editor.save_deck(), "saving again under the same name still works")
	_expect(not FileAccess.file_exists(editor.deck_path(PROBE_DECK)),
		"and does not resurrect the old file")

	# Back to the original name, because the checks below look for PROBE_DECK there.
	editor.save_deck(PROBE_DECK)

	# --- the custom preset ------------------------------------------------------------------
	MatchSetup.custom_deck_name = PROBE_DECK
	var cfg: Dictionary = MatchSetup.build_config("custom")
	_expect(cfg.get("preset") == "custom", "the config is the custom preset")
	var all_ids: Array = []
	all_ids.append_array(cfg["player_hand"])
	all_ids.append_array(cfg["player_deck"])
	all_ids.sort()
	_expect(all_ids == expected, "the player's deck is exactly the saved list, split into hand + deck (%d)" % all_ids.size())
	var opp: Array = []
	opp.append_array(cfg["opponent_hand"])
	opp.append_array(cfg["opponent_deck"])
	opp.sort()
	_expect(opp == expected, "and so is the opponent's — both players use the same deck")
	_expect(cfg["player_hand"].size() == 5, "the opening hand is 5 cards")
	_expect(cfg["player_deck"].size() == 2, "the rest is the deck (%d)" % cfg["player_deck"].size())
	_expect(cfg["player_field"].is_empty() and cfg["opponent_field"].is_empty(), "the custom match starts from an empty board")
	_expect(int(cfg["seed"]) != 0, "a seed is recorded so the match can be replayed")

	# Separate seeds mean the two draws are independent, not a mirror of each other.
	_expect(cfg["player_hand"] != cfg["opponent_hand"], "the two hands are shuffled independently, not mirrored")

	# --- failure paths ----------------------------------------------------------------------
	MatchSetup.custom_deck_name = "probe_missing_deck"
	_expect(MatchSetup.load_deck_ids().is_empty(), "a missing deck file loads as empty")
	var fell_back: Dictionary = MatchSetup.build_config("custom")
	_expect(int(fell_back.get("seed", 0)) != 0, "an empty custom deck falls back to a playable standard match")
	_expect(fell_back.has("player_deck"), "the fallback still has a deck")

	var junk := FileAccess.open(MatchSetup.deck_path("probe_junk_deck"), FileAccess.WRITE)
	if junk != null:
		junk.store_string("{\"not_a_deck\": true}")
		junk.close()
	_expect(MatchSetup.load_deck_ids("probe_junk_deck").is_empty(), "a file without a cards array loads as empty")

	# A deck of nothing but bogus ids must not produce a match with phantom cards.
	var bogus := FileAccess.open(MatchSetup.deck_path("probe_bogus_deck"), FileAccess.WRITE)
	if bogus != null:
		bogus.store_string("{\"cards\": [0, -3, 0]}")
		bogus.close()
	_expect(MatchSetup.load_deck_ids("probe_bogus_deck").is_empty(), "ids below 1 are filtered out")

	# --- deleting a deck --------------------------------------------------------------------
	# Deleting is destructive, so the confirmation lives in the picker where a mouse is needed. This is the
	# half that can be checked without one: the file goes, and deleting again reports failure, not success.
	_expect(MatchSetup.delete_deck(PROBE_DECK), "delete_deck removes a saved deck")
	_expect(not FileAccess.file_exists(MatchSetup.deck_path(PROBE_DECK)), "and the file is gone")
	_expect(not MatchSetup.delete_deck(PROBE_DECK), "deleting it again fails rather than pretending to work")
	var offered: Array = []
	for entry in MatchSetup.list_decks():
		offered.append(str(entry["name"]))
	_expect(not (PROBE_DECK in offered), "and the picker's list no longer offers it")

	# --- clean up ---------------------------------------------------------------------------
	for deck_key in [PROBE_DECK, PROBE_RENAMED, "probe_junk_deck", "probe_bogus_deck"]:
		var path: String = MatchSetup.deck_path(deck_key)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_expect(not FileAccess.file_exists(MatchSetup.deck_path(PROBE_DECK)), "the probe cleans up after itself")

	# Leave MatchSetup pointing at the real default, so a probe run cannot bleed into the menu.
	MatchSetup.custom_deck_name = MatchSetup.CUSTOM_DECK_NAME

	print("[DeckProbe] RESULT: %s (%d checks, %d failures)" % ["all checks passed" if _failures == 0 else "FAILURES", _checks, _failures])
	get_tree().quit()
