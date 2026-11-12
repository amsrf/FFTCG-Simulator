extends Node
## Match configuration + scene navigation (autoload `MatchSetup`).
##
## The menu builds a config and calls start_match(); game.gd reads it in
## _ready() via resolve_config(). Running game.tscn directly from the editor
## (no pending config) falls back to the "debug" preset, so the practice board
## still works without going through the menu.

const GAME_SCENE := "res://scenes/game/game.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const DECK_EDITOR_SCENE := "res://scenes/ui/deck_editor.tscn"

## One board per mechanic. Registered here so the Test Mode screen can list them; see test_grounds.gd for the boards
## themselves and the conventions they follow.
const TEST_GROUNDS := preload("res://scripts/core/test_grounds.gd")
const TEST_GROUNDS_MENU_SCENE := "res://scenes/ui/test_grounds_menu.tscn"

## Where the deck editor writes. Same directory and same default name, so a deck saved in the
## editor is the deck the custom preset plays without anything else having to be kept in step.
const DECK_DIR := "user://decks"
const CUSTOM_DECK_NAME := "default"
const DECK_PICKER_SCENE := "res://scenes/ui/deck_picker.tscn"

## Config for the match about to start. Empty = fall back to the debug preset.
var config: Dictionary = {}
var _demo_navigation: CanvasLayer
var _demo_config_backup: Dictionary = {}

## Which saved deck the "custom" preset plays. The editor's Play button sets it, so playing from the
## editor reads back the file you just saved rather than the default one.
var custom_deck_name: String = CUSTOM_DECK_NAME

## Which deck the editor should open. Empty = a brand new deck. Set by the picker immediately before it
## navigates, because a scene cannot receive an argument.
var editing_deck_name: String = ""

func get_presets() -> Array:
	# THE MAIN MENU IS UNCHANGED. Test grounds live behind their own "Test Mode" screen, so the everyday menu stays
	# short and the mechanic-specific boards do not read as ways to start a normal match.
	return ["custom", "ai", "standard", "debug"]

## The boards listed on the Test Mode screen.
func get_test_grounds() -> Array:
	return TEST_GROUNDS.names()

func describe_preset(preset: String) -> String:
	if TEST_GROUNDS.has(preset):
		return "%s  —  %s" % [TEST_GROUNDS.title(preset), TEST_GROUNDS.blurb(preset)]
	match preset:
		"custom":
			return "Custom Deck  (both players - saved in the Deck Editor)"
		"ai":
			return "Vs AI  (Practice Board - opponent plays cards and attacks)"
		"standard":
			return "Standard Match  (empty board - seeded shuffled decks)"
		"debug":
			return "Practice Board  (pre-placed cards for card testing)"
		_:
			return preset

func build_config(preset: String, overrides: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary
	if TEST_GROUNDS.has(preset):
		# A ground is a preset with a curated board; `overrides` still applies on top.
		cfg = TEST_GROUNDS.config(preset)
		for key in overrides:
			cfg[key] = overrides[key]
		return cfg
	match preset:
		"custom":
			cfg = _custom()
		"ai":
			# The practice board, but with a *playable* opponent. The debug board
			# leaves it one untapped Backup (1 mana), so it could never afford
			# anything; here it gets three mana sources and an affordable hand.
			cfg = _debug()
			cfg["preset"] = "ai"
			cfg["opponent_type"] = "ai"
			# AERITH ON THE PLAYER'S BACKUP LINE, for the S cost. Her ability needs a card with the SAME NAME discarded
			# from hand, and _debug() already puts one (64) in the opening hand — she is the source here. So the two are
			# deliberately both present: one on the board to activate, one in hand to spend.
			#
			# FIVE-BACKUP LIMIT. _debug() already fields five Backups, so adding Aerith would make six. Drop the
			# Red Mage Backup to keep the AI test board a legal five.
			for i in range(cfg["player_field"].size() - 1, -1, -1):
				if int(cfg["player_field"][i].get("id", -1)) == 3:
					cfg["player_field"].remove_at(i)
			cfg["player_field"].append({"id": 64, "tapped": false})
			# A SECOND FIRE PAIR SPLIT BY SQUALL, for party formation: Zack and Squall swap places, and 1 Auron (Fire)
			# lands beside Squall, so the row reads Auron | Squall | Red XIII | Zack. Red XIII + Zack are neighbours
			# (nothing moves); Auron + Red XIII have Squall between them (he is pushed aside).
			var zack_i: int = -1
			var squall_i: int = -1
			for i in range(cfg["player_field"].size()):
				match int(cfg["player_field"][i].get("id", -1)):
					12: zack_i = i
					41: squall_i = i
			if zack_i >= 0 and squall_i >= 0:
				var tmp = cfg["player_field"][zack_i]
				cfg["player_field"][zack_i] = cfg["player_field"][squall_i]
				cfg["player_field"][squall_i] = tmp
			cfg["player_field"].append({"id": 1, "tapped": false})   # Auron (Fire Forward 9000)
			# THREE FORWARDS + FIVE BACKUPS, the legal maximum for each row. The five Evokers are all wind,
			# which is exactly what 62 Valefor costs (5) — the old board had nine Backups, which is not a legal
			# field and made the perspective layout impossible to inspect.
			cfg["opponent_field"] = [
				{"id": 41, "tapped": false},   # Squall (ice Forward 6000)
				{"id": 43, "tapped": false},   # Snow (ice Forward)
				{"id": 71, "tapped": false},   # Zidane (Forward 3000)
				{"id": 68, "tapped": false},   # Evoker (wind Backup, cost 1)
				{"id": 68, "tapped": false},
				{"id": 68, "tapped": false},
				{"id": 68, "tapped": false},
				{"id": 68, "tapped": false},
			]
			# 62 Valefor FIRST: "Return all Forwards to their owners' hands" — no target to pick, so the AI
			# casts it on its first priority and the player watches their Forwards come back to hand.
			# 33 Argath is a cost-2 Forward whose ETB makes ITS OPPONENT discard 1 — so the AI playing it is how
			# the human's discard UI gets exercised.
			cfg["opponent_hand"] = [62, 33, 4, 55, 53]
			# GADOT 1-007 for the two-ETB stack test: entering puts two abilities on the stack, and their cards fly in
			# staggered. Red XIII (29, a cost-2 Fire Forward) is already in the hand for his "play a Fire Forward".
			cfg["player_hand"].append(7)
		"debug":
			cfg = _debug()
		_:
			cfg = _standard()
	for key in overrides:
		cfg[key] = overrides[key]
	return cfg

func start_match(preset: String, overrides: Dictionary = {}) -> void:
	config = build_config(preset, overrides)
	config["auto_pass"] = auto_pass
	get_tree().change_scene_to_file(GAME_SCENE)

# --- player settings ---------------------------------------------------------

const SETTINGS_PATH := "user://settings.cfg"
## Pass automatically when you get priority and have nothing you could do. On by default; the menu toggles it.
var auto_pass: bool = true

func _ready() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		auto_pass = bool(settings.get_value("play", "auto_pass", true))

func set_auto_pass(enabled: bool) -> void:
	auto_pass = enabled
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("play", "auto_pass", enabled)
	settings.save(SETTINGS_PATH)

func go_to_menu() -> void:
	close_online()
	if is_instance_valid(_demo_navigation):
		go_to_demo_menu()
		return
	config = {}
	get_tree().change_scene_to_file(MENU_SCENE)

func go_to_deck_picker() -> void:
	config = {}
	get_tree().change_scene_to_file(DECK_PICKER_SCENE)

## The Test Mode screen: one board per mechanic, separate from the main menu.
func go_to_test_grounds() -> void:
	config = {}
	get_tree().change_scene_to_file(TEST_GROUNDS_MENU_SCENE)

## Opens the editor on `name`. An EMPTY name means a brand new deck, and the editor starts blank — that is
## the difference between "edit this deck" and "create one", and it is carried by the name rather than a
## separate flag, so there is only one thing to get out of sync.
func go_to_deck_editor(deck_key: String = "") -> void:
	config = {}
	editing_deck_name = deck_key
	get_tree().change_scene_to_file(DECK_EDITOR_SCENE)

## Config a match should use: the pending one, else the debug preset.
func resolve_config() -> Dictionary:
	if config.is_empty():
		return _debug()
	return config

# --- online play -----------------------------------------------------------

const NET_SESSION := preload("res://scripts/net/net_session.gd")
## The open connection to the other player, if any. A child of this autoload, so it survives the scene change into
## the match.
var net: Node = null

## The deck this machine brings online: the custom deck from the Deck Editor, else the standard 1-50 list.
func online_deck() -> Array:
	var ids: Array = load_deck_ids(custom_deck_name)
	return ids if not ids.is_empty() else range(1, 51)

## A fresh session; any previous one is closed. The caller connects its signals, then calls host() or join().
func new_online_session() -> Node:
	close_online()
	net = NET_SESSION.new()
	add_child(net)
	net.match_ready.connect(func(cfg: Dictionary):
		config = cfg
		get_tree().change_scene_to_file(GAME_SCENE))
	return net

func close_online() -> void:
	if net != null and is_instance_valid(net):
		net.close()
		net.queue_free()
	net = null

## THE SAME MATCH ON BOTH MACHINES, each from its own side. Seat 1's deck is shuffled with `seed`, seat 2's with
## seed + 1, whichever machine builds it; then "player" is this machine's seat and "opponent" the other one.
func online_config(seed_value: int, local_seat: int, starting_seat: int, seat1_deck: Array, seat2_deck: Array,
		fields: Dictionary = {}, hand_extras: Dictionary = {}) -> Dictionary:
	var by_seat: Dictionary = {1: _shuffled(seat1_deck, seed_value), 2: _shuffled(seat2_deck, seed_value + 1)}
	var mine: Array = by_seat[local_seat]
	var theirs: Array = by_seat[3 - local_seat]
	var opening_mine: int = mini(5, mine.size())
	var opening_theirs: int = mini(5, theirs.size())
	return {
		"preset": "online",
		"auto_pass": auto_pass,
		"player_type": "local",
		"opponent_type": "mock",   # replaced by the session's RemoteAgent
		"local_seat": local_seat,
		"starting_player": 1 if starting_seat == local_seat else 2,
		"seed": seed_value,
		"shuffle": true,
		"player_hand": mine.slice(0, opening_mine) + _ids(hand_extras.get(str(local_seat), [])),
		"opponent_hand": theirs.slice(0, opening_theirs) + _ids(hand_extras.get(str(3 - local_seat), [])),
		"player_deck": mine.slice(opening_mine),
		"opponent_deck": theirs.slice(opening_theirs),
		"player_field": _field_entries(fields.get(str(local_seat), [])),
		"opponent_field": _field_entries(fields.get(str(3 - local_seat), [])),
		"first_phase": "first_main",
	}

## Card ids that crossed the network: JSON turns every number into a float.
func _ids(values) -> Array:
	var out: Array = []
	if values is Array:
		for v in values:
			out.append(int(v))
	return out

## Field entries that crossed the network: JSON turns every number into a float.
func _field_entries(entries) -> Array:
	var out: Array = []
	if entries is Array:
		for entry in entries:
			if entry is Dictionary:
				var copy: Dictionary = entry.duplicate()
				copy["id"] = int(copy.get("id", 0))
				copy["tapped"] = bool(copy.get("tapped", false))
				out.append(copy)
	return out

# --- custom decks ----------------------------------------------------------

func deck_path(deck_key: String = CUSTOM_DECK_NAME) -> String:
	return "%s/%s.json" % [DECK_DIR, deck_key]

## Deletes a deck file, reporting why when there is nothing to delete — so a caller never reports success for
## a file that was already gone.
##
## The CALLER confirms first. This is the only destructive operation on a deck and it does not ask.
func delete_deck(deck_key: String) -> bool:
	var path: String = deck_path(deck_key)
	if not FileAccess.file_exists(path):
		print("[MatchSetup] no deck to delete at %s" % path)
		return false
	var err: int = DirAccess.remove_absolute(path)
	if err != OK:
		print("[MatchSetup] could not delete %s (error %d)" % [path, err])
		return false
	print("[MatchSetup] deleted %s" % path)
	return true

## Card ids from a deck file, or [] when there is nothing usable there. Every failure prints why:
## silently falling back to a default deck would look like the editor had saved something it had not.
##
## An empty `name` means "the deck we are currently pointed at" (`custom_deck_name`), NOT the constant
## default: a caller that has just set custom_deck_name must be able to ask for it without repeating
## itself, or the two can disagree.
func load_deck_ids(deck_key: String = "") -> Array:
	var which: String = custom_deck_name if deck_key.is_empty() else deck_key
	var path: String = deck_path(which)
	if not FileAccess.file_exists(path):
		print("[MatchSetup] no deck at %s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[MatchSetup] cannot open %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary) or not parsed.has("cards"):
		print("[MatchSetup] %s is not a deck file" % path)
		return []
	var ids: Array = []
	for entry in parsed["cards"]:
		var id: int = int(entry)
		if id < 1:
			print("[MatchSetup] ignoring bogus card id %s in %s" % [str(entry), path])
			continue
		ids.append(id)
	return ids

## Every saved deck, as {name, face, count} — the ONE reader for what is actually on disk, so the picker and
## the editor cannot disagree about what a deck file contains.
##
## `face` is the card that represents the deck on the picker's tile. It defaults to the deck's FIRST card, so
## a deck saved before faces existed still shows something rather than a blank tile.
##
## Unreadable and malformed files are SKIPPED rather than listed: a tile that cannot be opened is worse than
## no tile at all, and the editor is where a broken file should get diagnosed.
func list_decks() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DECK_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var path: String = "%s/%s" % [DECK_DIR, file_name]
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if not (parsed is Dictionary) or not parsed.has("cards"):
			continue
		var ids: Array = parsed["cards"]
		var face: int = int(parsed.get("face", 0))
		if face < 1 and not ids.is_empty():
			face = int(ids[0])
		out.append({
			"name": str(parsed.get("name", file_name.get_basename())),
			"face": face,
			"count": ids.size(),
		})
	out.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	return out

## A match where BOTH players play the deck from the editor.
##
## Both sides get the SAME LIST shuffled with DIFFERENT SEEDS: the lists are identical, so it is the
## deck versus itself, but the two draws are independent rather than a mirror of each other.
##
## An empty or unreadable file falls back to the standard match rather than starting a game with no
## cards in it — and says so, so an empty Custom Deck is never a silent mystery.
func _custom() -> Dictionary:
	var ids: Array = load_deck_ids(custom_deck_name)
	if ids.is_empty():
		print("[MatchSetup] custom deck '%s' is empty — falling back to the standard match" % custom_deck_name)
		var fallback: Dictionary = _standard()
		fallback["preset"] = "custom"
		return fallback
	print("[MatchSetup] custom deck: %d cards from %s" % [ids.size(), deck_path(custom_deck_name)])
	var deck_seed: int = _pick_seed(0)
	var player_deck: Array = _shuffled(ids, deck_seed)
	var opponent_deck: Array = _shuffled(ids, deck_seed + 1)
	var opening: int = mini(5, player_deck.size())
	return {
		"preset": "custom",
		"opponent_type": "ai",
		"starting_player": 1,
		"seed": deck_seed,
		"shuffle": true,
		"player_hand": player_deck.slice(0, opening),
		"opponent_hand": opponent_deck.slice(0, opening),
		"player_deck": player_deck.slice(opening),
		"opponent_deck": opponent_deck.slice(opening),
		"player_field": [],
		"opponent_field": [],
		"first_phase": "first_main",
	}

## Standard match scaffold: shuffled decks, opening hand from the top of each,
## no pre-placed cards, turn starts at the Active Phase. The decklist itself is
## still fixed (1-50 vs 51-100); real deckbuilding is a later step.
func _standard() -> Dictionary:
	# Shuffle BEFORE slicing the opening hand, so the hand really is the top of
	# the shuffled deck. The seed lands in the config, so passing it back in
	# (overrides = {"seed": N}) reproduces the match exactly.
	var deck_seed: int = _pick_seed(0)
	var player_deck: Array = _shuffled(range(1, 51), deck_seed)
	var opponent_deck: Array = _shuffled(range(51, 101), deck_seed + 1)
	return {
		"preset": "standard",
		"opponent_type": "mock",
		"starting_player": 1,
		"seed": deck_seed,
		"shuffle": true,
		"player_hand": player_deck.slice(0, 5),
		"opponent_hand": opponent_deck.slice(0, 5),
		"player_deck": player_deck.slice(5),
		"opponent_deck": opponent_deck.slice(5),
		"player_field": [],
		"opponent_field": [],
		"first_phase": "first_main",
	}

## Seed 0 means "none chosen": pick one and record it, so the printed value can
## be passed back in to replay the same match.
func _pick_seed(seed_value: int) -> int:
	if seed_value != 0:
		return seed_value
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 999999)

## Fisher-Yates with a dedicated RNG. Array.shuffle() would use the global RNG,
## which cannot be reproduced from the config.
func _shuffled(cards: Array, seed_value: int) -> Array:
	var out: Array = cards.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	print("[MatchSetup] shuffled %d cards (seed %d)" % [out.size(), seed_value])
	return out

## Practice board: the original hardcoded debug setup.
func _debug() -> Dictionary:
	return {
		"preset": "debug",
		"opponent_type": "mock",
		"starting_player": 1,
		"seed": 0,
		"shuffle": false,
		# Opening hand (Aerith 64 + Evoker 68 for the Zack conditional-power test).
		"player_hand": [29, 30, 31, 32, 33, 6, 64, 68],
		"opponent_hand": [52, 53, 54, 55, 56],
		# TOP OF THE DECK IS IFRIT (4), which carries "ex_burst": "when_cast" — so the first damage the player
		# takes pulls it off the deck and immediately runs its cast effect at 4000 damage. Test with T (opponent
		# takes damage) and Y (player takes damage); Y is the one that puts Ifrit in the player's own zone.
		#
		# Built from ranges rather than a comprehension: GDScript's array comprehension has no `if`, and the
		# [i for i in ... if ...] form is a PARSE ERROR — which takes the whole autoload down, not just this line.
		"player_deck": [4] + range(1, 4) + range(5, 51),
		"opponent_deck": range(51, 101),
		# ZONES PRE-FILLED for testing the zone viewer: click one of these cards in-game, or press V / G.
		# Distinct ids so a card in the graveyard cannot be confused with one in the damage zone.
		"player_graveyard": [5, 6, 7],
		"player_damage": [8, 9],
		"opponent_graveyard": [57, 58],
		"opponent_damage": [59, 60],
		"player_field": [
			# 29 Red XIII carries printed First Strike, so a clash against anything without it takes two damage
			# steps with a priority window between them.
			{"id": 29, "tapped": false},
			{"id": 12, "tapped": false},
			{"id": 41, "tapped": false},
			{"id": 32, "tapped": true},
			{"id": 31, "tapped": false},
			{"id": 3, "tapped": false},
			# 100 Black Belt: tap + 1 EARTH to give a BLOCKING Forward +1000 until end of turn. It needs the Earth
			# Backup beside it or the skill can never be paid for — the other Backups here are Ice and Fire, and an
			# Earth cost cannot be paid with them.
			{"id": 100, "tapped": false},
			{"id": 105, "tapped": false},
			],
		"opponent_field": [
			{"id": 41, "tapped": false},
			{"id": 32, "tapped": true},
			{"id": 31, "tapped": false},
			# Zidane 1-071L: cannot_be_chosen protection test target.
			{"id": 71, "tapped": false},
			],
		"first_phase": "first_main",
	}


func start_demo(path: String) -> void:
	var catalog := preload("res://scripts/ui/demo_catalog.gd")
	var allowed := false
	for entry in catalog.entries():
		if entry.path == path:
			allowed = true
			break
	if not allowed:
		return
	_demo_config_backup = config.duplicate(true)
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("Could not open demo: " + path)
		return
	_demo_navigation = preload("res://scripts/ui/demo_navigation.gd").new()
	add_child(_demo_navigation)

func go_to_demo_menu() -> void:
	if is_instance_valid(_demo_navigation):
		_demo_navigation.queue_free()
		_demo_navigation = null
		config = _demo_config_backup
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/ui/demo_menu.tscn")
