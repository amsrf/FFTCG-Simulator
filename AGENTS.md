# AGENTS.md — FF TCG Simulator (Repository Guidelines)

Godot **4.7.2**, GDScript, GL Compatibility renderer. A 3D Final Fantasy TCG simulator.
Scenes: `main_menu.tscn` (main scene) → `game.tscn` (the match). Autoloads: `CardDatabase`, `GlobalVariables`, `MatchSetup` (`scripts/match_setup.gd`). A match is configured by `MatchSetup` before the scene change; `game.gd:_ready()` calls `start_match(MatchSetup.resolve_config())`, which falls back to the `debug` preset when `game.tscn` is run directly.

## Agent Rules (read first)

### Never run Godot
Do **not** launch Godot in any form — no editor, no `--headless`, `--quit-after`, `--check-only`, or `--script`. The user runs the project and will share any output. Do not execute the binary to "verify" a change; ask the user to run it instead.

### Context efficiency
- **Search before reading:** `grep` for the symbol first, then read only the surrounding lines.
- **Understand one function at a time:** read its definition and its immediate callers — not the entire file.
- **Debug narrowly:** read only the failing function and its direct dependencies.
- **Skip generated/vendored paths:** `addons/`, `.godot/`, and any `.import` / `.res` files, unless explicitly asked about assets.

## Build / Test / Run (reference — the user runs these)

No unit-test framework. Verification is manual: the user runs the project in the Godot 4.7.2 editor, or a headless boot to catch compile errors:

```bash
GODOT="/c/Users/KABUM/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
"$GODOT" --headless --path "C:\Users\KABUM\Desktop\TCG Project\TCG-Simulator-on-Godot" --quit-after 40
```

- Use the Godot **4.7.2** binary (nested inside a same-named folder under `~/Downloads`). `Godot_v4.4-stable_win64.exe` on the Desktop is the **wrong** version.
- Success = 0 `SCRIPT ERROR` / `Compile Error` lines. Add `res://game.tscn` as a positional arg to boot straight into a match (uses the `debug` preset) and also expect `Entering: 2` (FIRST_MAIN_PHASE); the menu boot cannot reach it, since it waits for a button press.
- Pre-existing harmless noise: `Condition "!is_inside_tree()" is true` spam and a `crystal.tscn` UID warning.
- `--check-only --script <file>` is unreliable here: autoloads are absent, so it false-errors with `Identifier not found: CardDatabase / GlobalVariables`.

## Architecture Map

| Path | Responsibility |
| --- | --- |
| `scripts/main_menu.gd` + `main_menu.tscn` | Entry point. Builds the menu UI in code; starts a preset match via `MatchSetup.start_match()`. |
| `scripts/match_setup.gd` (`MatchSetup` autoload) | Match config seam: presets (`standard`, `debug`), pending `config`, `start_match()` / `go_to_menu()` / `resolve_config()`. Future home of decklists, seed, opponent type. |
| `scripts/agents/` (`Agent` + `LocalAgent` / `MockAgent` / `AIAgent`) | Decision seam for priority, attacker and blocker declarations. `Agent` is the abstract base (all methods coroutines via `_settle()`); chosen per side in `Game.start_match()`. |
| `scripts/game.gd` (root `Game`) | Phase machine (`phases`, `next_phase`, `_enter_phase`), priority loop (`priority()` + `_priority_lock`), instruction executor (`_execute_instructions` → `_process_next_instruction` → `_resolve_executor`), targeting flow, state-based actions (`enforce_game_state_rules`), controller damage. `start_match(config)` builds the board; `agent_for()` / `controller_for()` / `side_for()` map player ids. |
| `battle_field.gd` (`Field`) | Per-player front/back card arrays, `play_card()` + ETB, auras, conditional-power registry, targeting, break detection, `end_phase_cleanup()`. |
| `stack.gd` (`Stack`) | Stack list + effect copies; skill/summon/S-cost flows. `resolve_top_effect()` awaits `resolution_complete`. |
| `assistant.gd` (`Assistant`) | All modal UI via `show_modal()`; pass-priority button; mana accumulator + `can_pay_cost()`. |
| `scripts/card.gd` (`Card`) | Card model + per-card UI/state. Power/damage, status effects, `power_array` buffs, `card_effects`, targeting predicates (`is_type`, `is_element`, `check_controller`, `is_named`, `is_cost_lower_than`). |
| `power_display.gd` | The `PowerDisplay` Label3D on each card; shows `power/accumulated_damage`. |
| `scripts/hand.gd` (`Hand`) | Hand layout, mana selection, choose-card mode, `charge()`/`discard_card()`. |
| `scripts/player_side.gd` (`PlayerSide`) | Player-level zones; `take_damage()` moves deck cards into the Damage Zone. |
| `scripts/hand_card_state.gd`, `scripts/field_card_state.gd` | Drag/release behavior per zone; swapped in `Card._update_state()`. |
| `area_3d.gd`, `big_button.gd` | 3D button primitives (signals, hover, enable/disable, autofit). |
| `assets/card_database.json`, `assets/card_effects.json` | Data loaded by the `CardDatabase` autoload. |

Node tree + all signal connections live at the bottom of `game.tscn` (read it before changing inter-module wiring).

## Rules Implemented

- **Phases:** ACTIVE → DRAW → FIRST_MAIN → ATTACK_PREP → ATTACK_DECL → BLOCKER_DECL → DAMAGE_RES → (loop to ATTACK_PREP) → SECOND_MAIN → END. Turns **alternate** (`turn_owner = 3 - turn_owner` at end of turn); the turn owner untaps in ACTIVE and draws in DRAW. Both players get priority each round (turn owner first).
- **Who acts is decided by the agent seam.** `Game.agent_for(player_id)` → `Agent` (`scripts/agents/`): `LocalAgent` (human UI), `MockAgent` (passes, never attacks/blocks), `AIAgent` (Phase 3 stub extending MockAgent). Chosen from `config["opponent_type"]`. The loop only calls `take_priority()`, `decide_attacker()`, `decide_blocker()` — targeting/mana/hand choices are still on the local UI path.
- **Damage:** `Card.accumulated_damage` counts **up**. Break iff `accumulated_damage >= power` (equal damage breaks). `power <= 0` → put into Graveyard, which is **not** a break (no break triggers, `unbreakable` doesn't apply). End Phase cleanup resets all damage and expires "until end of turn" effects.
- **Zones:** incoming damage → Damage Zone (cards off the deck); breaks/removals → Graveyard (= Break Zone).
- **Effects are data-driven.** Keywords: `when_enter_field`, `when_attack`, `when_cast`, `when_cause_damage_to_player`, `when_enter_break_from_field`, `skill`, `aura`, `conditional_power`. An instruction is `{name: <action>, author: <executor>, argument}`; executors resolve in `Game._resolve_executor` (`card`, `target`, `game`, `player`, `opponent`, `field`, `hand`, `deck`, `assistant`).
- **Target legality** = `choose_target` criteria (checked on the **candidate**) **and** the candidate's `cannot_be_chosen` protection (checked against the **source**). `request_target()` / `set_viable_targets()` / `has_viable_target()` take an explicit `source_kind` (`"Summon"` / `"Ability"`) because ability targeting is requested with the field card, which carries no `effect_kind`. A click is only accepted when `is_valid_target` is true (`Field.set_target_card()`); that flag comes from `set_viable_targets()`. Protection schema: `{ sources: [...], controller: "opponent" }`.

## Conventions

- GDScript, **tabs** for indentation.
- Type explicitly when inference can't work: `var x: Card = ...` not `var x := ...`. `:=` fails on untyped/uninferable expressions (untyped return values, parenthesized boolean expressions) — this has caused repeated parse errors.
- JSON data must be strict — **no trailing commas**.
- Card ids are 1-based ints; `string_id` keys into `card_effects`.
- Element codes are single chars: 火 氷 風 土 雷 水 光 闇 (+ `neutral`). UI text is English.
- Only `controller == "player"` cards are interactive; guard opponent cards with `controller != "player"`.
- Fail loudly: use `push_error()` on unknown executors/actions/missing targets rather than silent returns.

## Gotchas

- **State ownership:** match state (`phase`, `priority_holder`, `turn_owner`, `phase_index`) is owned by `Game` and must not be copied elsewhere. `Field.phase` is a read-through getter to `Game.phase`. `GlobalVariables` holds only local presentation state: hand-layout constants, the UI signals, and the input mode.
- **Input mode is derived, never assigned.** `effective mode = top of modal stack OR base mode`. `Game._enter_phase()` calls `set_base_mode(default_mode_for(phase))`; modal flows call `push_modal(...)` / `pop_modal(...)` (`TARGET`, `PAYING_COST`, `CHOOSE_CARD_IN_HAND`, `ATTACKING`); `refresh_mode()` re-applies the layers without disturbing an open modal. There is deliberately **no `set_player_mode`** — don't reintroduce one.
- **A modal is popped by the same layer that pushed it,** exactly once. Target cancel is driven by the `target_cancel` signal into Field *and* Stack, so only `Assistant.on_target_cancel()` / `on_target_complete()` pop `TARGET`.
- Backups store `"power": "0"`, so zero-power/breakable scans must stay limited to `front_cards` (Forwards) — scanning all field cards deletes every Backup.
- Opponent hand reuses `Hand.tscn`; behavior is gated by `controller`.
- `Card.power_label` is `@onready` — null until the card enters the tree.
- `END_PHASE` has no priority window: cleanup runs immediately, so end-of-turn auto-abilities can't resolve first yet.
- `activated_ability` in `card_effects.json` is not wired (only `skill` is).
- Intentionally kept dead code: `scripts/ManaCost.gd`, `Stack.process_next_effect()`, `Game.pop_stack()` / `Stack.pop_stack()`. Since Phase 2 these are also unused: `Game.MOCK_opponent_pass_piority()`, `Game.TEST_blocker()` / `pass_priority()`, `Field.untap_all_cards()`.
- `LocalAgent.decide_attacker()` enables `Player_Mode.ATTACKING`; for a non-local turn owner the phase stays in `INSTANT_SPEED_TIME` on purpose — setting `NO_PRIORITY` there hides the pass button and deadlocks the priority loop.

## Changelog

Maintain `CHANGELOG.md` with `## [Unreleased] — YYYY-MM-DD` sections using Added / Fixed / Changed / Known Issues. Add to the current date's section (don't create duplicate date headings); include file/method names and note unfinished work under Known Issues.
