extends Node
## Match configuration + scene navigation (autoload `MatchSetup`).
##
## The menu builds a config and calls start_match(); game.gd reads it in
## _ready() via resolve_config(). Running game.tscn directly from the editor
## (no pending config) falls back to the "debug" preset, so the practice board
## still works without going through the menu.

const GAME_SCENE := "res://game.tscn"
const MENU_SCENE := "res://main_menu.tscn"

## Config for the match about to start. Empty = fall back to the debug preset.
var config: Dictionary = {}

func get_presets() -> Array:
	return ["ai", "standard", "debug"]

func describe_preset(preset: String) -> String:
	match preset:
		"ai":
			return "Vs AI  (Practice Board - opponent plays cards and attacks)"
		"standard":
			return "Standard Match  (empty board - deck not shuffled yet)"
		"debug":
			return "Practice Board  (pre-placed cards for card testing)"
		_:
			return preset

func build_config(preset: String, overrides: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary
	match preset:
		"ai":
			# The practice board, but with a *playable* opponent. The debug board
			# leaves it one untapped Backup (1 mana), so it could never afford
			# anything; here it gets three mana sources and an affordable hand.
			cfg = _debug()
			cfg["preset"] = "ai"
			cfg["opponent_type"] = "ai"
			cfg["opponent_field"] = [
				{"id": 41, "tapped": false},
				{"id": 31, "tapped": false},
				{"id": 32, "tapped": false},
				{"id": 3, "tapped": false},
				{"id": 71, "tapped": false},
			]
			# Dark Knight x2 (cost 3/4), Summoner (cost 3), Hades (Summon — the
			# AI skips it), Evoker (cost 1). None of these needs a target.
			cfg["opponent_hand"] = [55, 54, 53, 52, 68]
		"debug":
			cfg = _debug()
		_:
			cfg = _standard()
	for key in overrides:
		cfg[key] = overrides[key]
	return cfg

func start_match(preset: String, overrides: Dictionary = {}) -> void:
	config = build_config(preset, overrides)
	get_tree().change_scene_to_file(GAME_SCENE)

func go_to_menu() -> void:
	config = {}
	get_tree().change_scene_to_file(MENU_SCENE)

## Config a match should use: the pending one, else the debug preset.
func resolve_config() -> Dictionary:
	if config.is_empty():
		return _debug()
	return config

## Standard match scaffold: opening hand from the top of each deck, no
## pre-placed cards, turn starts at the Active Phase. Shuffling and real
## decklists are not wired yet (see "shuffle" / "opponent_type" keys).
func _standard() -> Dictionary:
	var player_deck: Array = range(1, 51)
	var opponent_deck: Array = range(51, 101)
	return {
		"preset": "standard",
		"opponent_type": "mock",
		"starting_player": 1,
		"seed": 0,
		"shuffle": false,
		"player_hand": player_deck.slice(0, 5),
		"opponent_hand": opponent_deck.slice(0, 5),
		"player_deck": player_deck.slice(5),
		"opponent_deck": opponent_deck.slice(5),
		"player_field": [],
		"opponent_field": [],
		"first_phase": "first_main",
	}

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
		"player_deck": range(1, 51),
		"opponent_deck": range(51, 101),
		"player_field": [
			{"id": 12, "tapped": false},
			{"id": 41, "tapped": false},
			{"id": 32, "tapped": true},
			{"id": 31, "tapped": false},
			{"id": 3, "tapped": false},
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
