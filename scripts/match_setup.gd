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
			return "Standard Match  (empty board - seeded shuffled decks)"
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
				{"id": 41, "tapped": false},   # Squall (Forward 6000)
				{"id": 31, "tapped": false},   # Chemist (ice Backup)
				{"id": 32, "tapped": false},   # Chemist (ice Backup)
				{"id": 32, "tapped": false},   # Chemist (ice) — mana for a 2nd play
				{"id": 3, "tapped": false},    # Red Mage (fire Backup)
				{"id": 71, "tapped": false},   # Zidane (Forward 3000)
			]
			# Ifrit first (Summon, fire, cost 1) so the AI casts a Summon and
			# picks a target, and still has ice mana left for a Forward; then
			# Dark Knight x2 (cost 3/4), Summoner (cost 3), Hades (Summon,
			# cost 5 — deliberately unaffordable, to prove the AI declines it
			# instead of starting a payment it cannot finish).
			cfg["opponent_hand"] = [4, 55, 53, 54, 52]
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
