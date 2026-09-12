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
- **The scripts are split across two folders:** `battle_field.gd`, `stack.gd`, `assistant.gd`, `power_display.gd` are at the **repo root**, while `game.gd`, `card.gd`, `hand.gd`, `player_side.gd` are in `scripts/`. `grep -r` for the filename rather than guessing a path — a wrong guess costs a round trip.
- **Warnings arrive in batches.** The user runs Godot and pastes the warning list (`UNUSED_*`, `SHADOWED_VARIABLE`, `Case mismatch …`). Fix every line, then sweep for the same *class* (`grep` for other unused private vars, other case-mismatched `res://` paths) instead of waiting for the next run.

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
- **Who acts is decided by the agent seam.** `Game.agent_for(player_id)` → `Agent` (`scripts/agents/`): `LocalAgent` (human: pass button, attacker clicks, **blocker clicks**), `MockAgent` (passes, never attacks/blocks), `AIAgent` (plays an affordable card in a main phase; attacks with its strongest Forward that does not trade down, keeping one home to block; blocks only with a strictly bigger Forward). Chosen from `config["opponent_type"]`. Two method shapes: **pull** (`decide_attacker`, `decide_blocker`, `pay_cost` — return the answer) and **drive** (`choose_target`, `choose_card_in_hand` — perform the inputs a human would have clicked, then let the existing signal continuation run; `LocalAgent` does nothing for those because the human *is* the input).
- **Damage:** `Card.accumulated_damage` counts **up**. Break iff `accumulated_damage >= power` (equal damage breaks). `power <= 0` → put into Graveyard, which is **not** a break (no break triggers, `unbreakable` doesn't apply). End Phase cleanup resets all damage and expires "until end of turn" effects.
- **Zones:** incoming damage → Damage Zone (cards off the deck); breaks/removals → Graveyard (= Break Zone).
- **Win condition:** a player loses at `PlayerSide.DEFEAT_DAMAGE` (7) cards in their damage zone, and also if their deck cannot supply the cards for damage. `PlayerSide.take_damage()` emits `damaged(self)`, which `Game._on_player_side_damaged()` listens to — so **any** damage source, present or future, is covered; don't re-check defeat at call sites. `Game._end_match()` sets `match_over`, which `next_phase()` checks to stop the machine before returning to the menu.
- **Effects are data-driven.** Keywords: `when_enter_field`, `when_attack`, `when_cast`, `when_cause_damage_to_player`, `when_enter_break_from_field`, `skill`, `aura`, `conditional_power`. An instruction is `{name: <action>, author: <executor>, argument}`; executors resolve in `Game._resolve_executor` (`card`, `target`, `game`, `player`, `opponent`, `field`, `hand`, `deck`, `assistant`).
- **Target legality** = `choose_target` criteria (checked on the **candidate**) **and** the candidate's `cannot_be_chosen` protection (checked against the **source**). `request_target()` / `set_viable_targets()` / `has_viable_target()` take an explicit `source_kind` (`"Summon"` / `"Ability"`) because ability targeting is requested with the field card, which carries no `effect_kind`. A click is only accepted when `is_valid_target` is true (`Field.set_target_card()`); that flag comes from `set_viable_targets()`. Protection schema: `{ sources: [...], controller: "opponent" }`.

## Conventions

- GDScript, **tabs** for indentation.
- Type explicitly when inference can't work: `var x: Card = ...` not `var x := ...`. `:=` fails on untyped/uninferable expressions (untyped return values, parenthesized boolean expressions) — this has caused repeated parse errors.
- JSON data must be strict — **no trailing commas**.
- Card ids are 1-based ints; `string_id` keys into `card_effects`.
- Element codes are single chars: 火 氷 風 土 雷 水 光 闇 (+ `neutral`). UI text is English.
- Only `controller == "player"` cards are interactive; guard opponent cards with `controller != "player"`.
- **Asset paths must match the on-disk case exactly** (`res://card.tscn`, not `res://Card.tscn`). Windows loads it anyway but exports are case-sensitive — Godot warns with a `Case mismatch opening requested file` line authored to whichever script triggered the load.
- Keep the tree free of editor junk: Godot's atomic saves leave `<file><random>.tmp` next to the original (e.g. `game.tscn1234.tmp`). They are never read and just clutter the project scan.
- Fail loudly: use `push_error()` on unknown executors/actions/missing targets rather than silent returns. The same goes for *outcomes*: if a precondition fails and the game silently does nothing, the player just sees a no-op or a hang — emit a signal so a listener can react instead (see Gotchas).

## Gotchas

- **State ownership:** match state (`phase`, `priority_holder`, `turn_owner`, `phase_index`) is owned by `Game` and must not be copied elsewhere. `Field.phase` is a read-through getter to `Game.phase`. `GlobalVariables` holds only local presentation state: hand-layout constants, the UI signals, and the input mode.
- **Input mode is derived, never assigned.** `effective mode = top of modal stack OR base mode`. `Game._enter_phase()` calls `set_base_mode(default_mode_for(phase))`; modal flows call `push_modal(...)` / `pop_modal(...)` (`TARGET`, `PAYING_COST`, `CHOOSE_CARD_IN_HAND`, `ATTACKING`, `BLOCKING`); `refresh_mode()` re-applies the layers without disturbing an open modal. There is deliberately **no `set_player_mode`** — don't reintroduce one.
- **Declaration buttons follow the same rule as the modals.** `ASSISTANT.set_declare_attack_button()` / `set_declare_block_button()` are driven by `Field.attacker_changed` / `Field.blocker_changed` — and **both signals fire for either side**, so their handlers (`Game._on_field_attacker_changed` / `_on_field_blocker_changed`) must bail unless the matching mode (`ATTACKING` / `BLOCKING`) is open. Without that guard the human is offered a button for the opponent's attacker/blocker.
- **A modal is popped by the same layer that pushed it,** exactly once. Target cancel is driven by the `target_cancel` signal into Field *and* Stack, so only `Assistant.on_target_cancel()` / `on_target_complete()` pop `TARGET`.
- **Blocking invariants:** `Card.declare_blocker()` only *records* the blocker — via `Field.blocker_card`, which survives `_clean_instruction_stack()` — and the single clash lives in `DAMAGE_RESOLUTION`. Never clash at declaration time (it would apply twice and be invisible to the damage step).
- **`Field.attacker_changed` fires for both sides** (both attackers use the same Field). Anything reacting to it must check the input mode: `Game._on_field_attacker_changed()` bails unless `player_mode == ATTACKING`, otherwise the human is offered an Attack button for the opponent's attacker.
- **Playing a card goes through the shared UI pipeline, whoever plays it.** `Game.play_card_for(player_id, card)` → `Hand.charge()` → `charge_start` → Stack parks it + Assistant sets `mana_cost` and opens the payment modal. Non-local owners then pay via `Agent.pay_cost()` (taps their Backups through `Field.add_card_to_mana_conversion`, which feeds `Assistant.can_pay_cost()`) and the game calls `Assistant.on_charge_complete()` itself. The human's modal buttons are hidden while another player pays.
- **`Stack.cards` means "legally on the stack" — nothing else.** A card awaiting its cost is only *parked* on the Stack node (`Stack.park_card()`, tracked by `casting_card` / `summon_casting_card`): visible, but neither in `cards` nor committed or revealed. Character cards (Forward/Backup) **never** enter `cards` — once paid, `cast_card()` plays them straight to the field. Only a Summon becomes a stack object, and only in `_commit_summon_to_stack()` after payment + target. Keeping `cards` honest matters because `stack_length()` drives the priority loop's "did an action happen" test.
- **Stack layout goes through `layout_cards()`** = `cards` + the parked card (if any). `calculate_total_width()` and `update_card_positions()` use it. Computing the row from `cards` alone leaves the parked card out of the width, which offsets *every* card — that is why a card awaiting payment sat visibly off-centre.
- **Every `Hand` needs the same Assistant connections, not just `Player/Hand`.** `charge_start`, `charge_complete`, `charge_cancelled`, `target_cancel` and `selected_cards_for_mana_has_changed` must be wired for `Opponent/Hand` too. Missing `charge_cancelled` meant a cancelled payment could not be returned to hand, so the card stayed parented to the Stack — frozen on screen forever.
- **`Field.play_card()` cannot infer the side** — it defaults to the local player. Callers must pass `is_opponent` (`Stack.cast_card()` does).
- **The mana-crystal marker is owned by `Card`.** Use `Card.show_mana_crystal()` / `clear_mana_crystal()` (both null-safe); never dereference `crystal_instance` directly. It used to be created only by the two click handlers, so any non-UI selection (an agent paying a cost) left it null and `Card.reset()` crashed on `queue_free` in base `Nil` — `add_card_to_mana_conversion` now creates it and `remove_*` / `reset()` clear it, so there is one creation site.
- Backups store `"power": "0"`, so zero-power/breakable scans must stay limited to `front_cards` (Forwards) — scanning all field cards deletes every Backup.
- Opponent hand reuses `Hand.tscn`; behavior is gated by `controller`.
- `Card.power_label` is `@onready` — null until the card enters the tree.
- `END_PHASE` has no priority window: cleanup runs immediately, so end-of-turn auto-abilities can't resolve first yet.
- `activated_ability` in `card_effects.json` is not wired (only `skill` is).
- Intentionally kept dead code: `scripts/ManaCost.gd`, `Stack.process_next_effect()`, `Game.pop_stack()` / `Stack.pop_stack()`. Since Phase 2 these are also unused: `Game.MOCK_opponent_pass_piority()`, `Game.TEST_blocker()` / `pass_priority()`, `Field.untap_all_cards()`.
- `ATTACKING` / `BLOCKING` are pushed by `Game._enter_phase` for a **local** declarer only, and popped as soon as the declaration ends (so the pass button returns for the priority round that follows). For a non-local turn owner the phase stays in `INSTANT_SPEED_TIME` on purpose — setting `NO_PRIORITY` there hides the pass button and deadlocks the priority loop.
- **Code after `await priority()` runs LATE.** In an `_enter_phase` arm, the statements following `await priority()` (e.g. `field.reset_attacker()` / `reset_blocker()`) do **not** run when that priority round ends — they run only once the *next* phase has been entered and its own awaits unwind. So per-combat state must also be established at the **start** of the consuming step: the blocker arm calls `field.reset_blocker()` for exactly this reason. Never assume "reset after priority" means "before the next combat uses it".
- **A duplicated rule must stay in sync.** `AIAgent._can_afford()` re-implements `Assistant.can_pay_cost()` element by element so the AI never *starts* a payment it cannot finish. `Assistant` is the authority; the AI copy is only an optimisation. Change one, change both.
- **A silent early `return` on a precondition hides an outcome.** Two bugs came from this: `PlayerSide.take_damage()` returned without a word when the deck was empty (it now emits `damaged`), and `Stack._on_assistant_charge_cancelled()` popped a card it never handed back (frozen on screen). When a precondition fails, emit/report so a listener can react — don't just bail.
- `Field.reset_attacker()` nulls `attacker_card` but never clears what `set_attacker_status(true)` set (`status_effects['attacking']` + a z-offset); `reset_blocker()` does it properly (validity- and `is_on_field()`-guarded). Known wart — see the CHANGELOG's Next Steps.

## Changelog

Maintain `CHANGELOG.md` with `## [Unreleased] — YYYY-MM-DD` sections using Added / Fixed / Changed / Known Issues. Add to the current date's section (don't create duplicate date headings); include file/method names and note unfinished work under Known Issues.
