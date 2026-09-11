# Global.gd
extends Node
## Shared autoload for **local presentation state only**.
##
## Match state (phase, priority holder, turn owner) lives on `Game`. Do not
## duplicate it here — this script owns the human's input mode, the event
## signals the UI listens to, and the hand layout constants.
##
## Input mode is *derived*, never assigned directly:
##     effective = top of the modal stack  OR  the base mode for the phase
## `Game` sets the base from the phase; flows push/pop their own modal. That is
## why closing a modal is symmetric — popping simply reveals the base again.

# Hand layout constants (presentation)
var _hand_center = Vector3(0, 2, -2.9)
var _card_width = 0.429
var _card_height = 0.6
var _card_spacing = -0.15
var _hand_rotation = Vector3(36, -180, 0)
var focus_card_id = null

## What the human may do. FREE / INSTANT_SPEED_TIME / ATTACKING / NO_PRIORITY
## describe a phase; PAYING_COST / TARGET / CHOOSE_CARD_IN_HAND are modals.
enum Player_Mode { FREE, PAYING_COST, ATTACKING, TARGET, NO_PRIORITY, INSTANT_SPEED_TIME, CHOOSE_CARD_IN_HAND }

## Current effective mode. Read it with get_player_mode(); it is recomputed by
## _refresh_mode() from the two layers below.
var player_mode: Player_Mode = Player_Mode.FREE
var _base_mode: Player_Mode = Player_Mode.FREE
var _modal_stack: Array = []

signal focus_card(id)
signal player_mode_change(pm : Player_Mode)

enum Phase {
	ACTIVE_PHASE,
	DRAW_PHASE,
	FIRST_MAIN_PHASE,
	ATTACK_PREPARATION_STEP,
	ATTACK_DECLARATION_STEP,
	BLOCKER_DECLARATION_STEP,
	DAMAGE_RESOLUTION_STEP,
	COMBAT_END_STEP,
	SECOND_MAIN_PHASE,
	END_PHASE
}

## Default input mode for each phase. `Game._enter_phase()` applies this as the
## base mode; phases that need something narrower push a modal instead.
const PHASE_DEFAULT_MODE: Dictionary = {
	Phase.ACTIVE_PHASE: Player_Mode.NO_PRIORITY,
	Phase.DRAW_PHASE: Player_Mode.NO_PRIORITY,
	Phase.FIRST_MAIN_PHASE: Player_Mode.FREE,
	Phase.ATTACK_PREPARATION_STEP: Player_Mode.INSTANT_SPEED_TIME,
	Phase.ATTACK_DECLARATION_STEP: Player_Mode.INSTANT_SPEED_TIME,
	Phase.BLOCKER_DECLARATION_STEP: Player_Mode.INSTANT_SPEED_TIME,
	Phase.DAMAGE_RESOLUTION_STEP: Player_Mode.INSTANT_SPEED_TIME,
	Phase.COMBAT_END_STEP: Player_Mode.INSTANT_SPEED_TIME,
	Phase.SECOND_MAIN_PHASE: Player_Mode.FREE,
	Phase.END_PHASE: Player_Mode.INSTANT_SPEED_TIME
}

func default_mode_for(p: Phase):
	return PHASE_DEFAULT_MODE.get(p, Player_Mode.FREE)

## Phase-level mode. Called by `Game` when the phase changes.
func set_base_mode(mode: Player_Mode) -> void:
	_base_mode = mode
	_refresh_mode()

## A modal flow opened: its mode takes over until the matching pop_modal().
func push_modal(mode: Player_Mode) -> void:
	_modal_stack.append(mode)
	_refresh_mode()

## The flow that opened `mode` finished. Popping reveals the base (or the next
## modal down) — no need to know what the previous mode was.
func pop_modal(mode: Player_Mode) -> void:
	var idx: int = _modal_stack.rfind(mode)
	if idx == -1:
		push_warning("[Interaction] pop_modal(%s) without a matching push" % mode)
		return
	_modal_stack.remove_at(idx)
	_refresh_mode()

func has_modal() -> bool:
	return not _modal_stack.is_empty()

func modal_top():
	return _modal_stack.back() if not _modal_stack.is_empty() else null

## Re-apply base + modals. Use after a flow that only wants to "normalise" the
## mode (leaves any open modal in place, unlike assigning a mode directly).
func refresh_mode() -> void:
	_refresh_mode()

func _refresh_mode() -> void:
	var mode: Player_Mode = _modal_stack.back() if not _modal_stack.is_empty() else _base_mode
	player_mode = mode
	player_mode_change.emit(mode)

func get_player_mode():
	return player_mode

# Getters
func get_hand_center():
	return _hand_center

func get_card_width():
	return _card_width

func get_card_spacing():
	return _card_spacing

func get_hand_rotation():
	return _hand_rotation

# Setters
func set_hand_center(value):
	_hand_center = value

func set_card_width(value):
	_card_width = value

func set_card_spacing(value):
	_card_spacing = value
