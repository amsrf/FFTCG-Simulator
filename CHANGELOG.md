# Changelog

All notable changes to the FF TCG Simulator project.

## [Unreleased] — 2026-09-11

### Added

#### Targeting Protection (Zidane 1-071L)
- `Card.effect_kind` (`"Summon"` / `"Ability"`) set on stack copies (`stack.gd`: `_commit_summon_to_stack()`, `add_skill_activation_proxy()`, `create_card()`).
- `Card.get_effect_kind()` — returns `effect_kind`, with a fallback derivation (`type == "Summon"` → Summon; any effect copy → Ability).
- `Card.can_be_chosen_by(source)` — evaluates `cannot_be_chosen` protection against the **source** of a targeting effect (the inverse of `choose_target`, which is evaluated on the candidate).
- `BattleField._card_matches_criteria(card, criteria, source, source_kind)` now also applies protection. `set_viable_targets()` / `has_viable_target()` / `request_target()` take an explicit `source_kind` (`"Summon"` / `"Ability"`), needed because ability targeting is requested with the field card, which carries no `effect_kind`.
- `assets/card_effects.json`: Zidane `"71"` → `cannot_be_chosen: { sources: ["Summon","Ability"], controller: "opponent" }`.

#### Triggered Auto-Abilities (Auron 1-001H)
- `stack.gd: begin_triggered_ability(source, keyword)` puts a triggered auto-ability on the stack during rules processing, before priority.
- `scripts/game.gd: cause_damage()` triggers `when_cause_damage_to_player` for the attacking Forward.
- Triggers go on the stack **immediately**; "may" choices are made at **resolution** time, not trigger time.
- `GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND` — hand selection mode with crystal indicators.
- `scripts/hand.gd`: `begin_choose_card()`, `end_choose_card()`, `toggle_effect_card_selection()`, `has_card_matching_criteria()`, `remove_card_for_free_play()`.
- `assistant.gd`: `show_choose_card_buttons()` ("Play card" disabled until a legal card is selected / "Don't play card"), `choose_card_finished(play)` signal.
- `scripts/player_side.gd: may_play_for_free()` — plays the chosen Backup to the field tapped, for free.
- `stack.gd: resolve_top_effect()` is now async and waits for `resolution_complete`, so the priority loop does not advance while a resolution modal is open.
- `assets/card_effects.json`: Auron `"1"` entry with `when_cause_damage_to_player` + `choose_card` (`is_type: Backup`, `is_element: Fire`).

#### Conditional Power Effects (Zack 1-012R)
- `scripts/card.gd`: `is_named()` and `current_conditional_bonus` tracking.
- `battle_field.gd`: `_conditional_effects` registry with `register_conditional_effects()`, `unregister_conditional_effects()`, `recompute_conditional_power()`, and `_condition_met()` (linear scan, no index).
- Recomputation is event-driven: runs only in `play_card()` and `remove_card()` — never per frame.
- `assets/card_effects.json`: Zack `"12"` entry with `when_enter_field` (deal 2000 to an opponent Forward) and `conditional_power` (+2000 while the player controls Aerith).

#### Special Ability Cost — S Symbol (Aerith 1-064R)
- `assets/card_effects.json`: Aerith `"64"` skill entry with `"s_cost": true`, `"tap": true`.
- Two-step cost flow: first choose a card in hand sharing a name with the source ("Discard"/"Cancel"), then the regular mana payment step.
- The S discard is deferred until the final skill commit; cancelling at any step refunds everything.
- `stack.gd`: `begin_s_cost_selection()`, `_on_choose_card_finished()`, S-cost state cleared in `_clear_skill_proxy()`.
- `scripts/hand.gd: discard_card()` — moves the chosen hand card to the graveyard.

#### Button System Refactor
- `area_3d.gd`: `button_pressed` / `button_hovered` / `button_unhovered` signals, real hover detection, `set_input_enabled()` toggles `input_ray_pickable` so hidden buttons cannot eat clicks.
- `big_button.gd`: hover/press/disabled visuals (tweened scale + material dimming), `configure()`, `show_button()`/`hide_button()`, `pressed` signal, text autofit (font shrinks to fit), viewport reduced from 2048×2048 to 1024×1024.
- `assistant.gd`: unified `show_modal()` API; all flows (attack, targeting, payment, choose-card) go through it.

#### Player / Opponent Hand Unification
- Opponent hand now uses the same `Hand.tscn` scene as the player (`game.tscn`).
- `scripts/hand_card_state.gd`: `controller != "player"` guards keep opponent cards inert.
- Deleted `opponent_hand.gd`, `opponent_hand.tscn`, `opponenet_hand.gd` and their `.uid` files.

#### Damage Accumulation & Break Rules
- `Card.accumulated_damage` replaces `Card.life`: damage now accumulates upward instead of depleting a life total.
- `Card.is_broken()` — true when accumulated damage **is equal to or greater than** current power.
- `Card.has_zero_power()` — true when current power is 0 or less.
- `Card.clear_damage()` — resets accumulated damage (used by End Phase cleanup).
- `Field.get_zero_power_cards()` — Forwards at 0 or less power, handled as a separate removal event from breaks.
- `Field.end_phase_cleanup()` (renamed from `turn_end_reset()`).
- `Game.put_card_into_graveyard()` — the non-break removal path; fires no break triggers and ignores `unbreakable`.
- `Game._send_card_to_graveyard()` — shared routing for both removal paths.

### Fixed

- **Target clicks weren't validated.** `Field.set_target_card()` accepted a click on *any* card; `is_valid_target` only controlled the on-card indicator, so Zidane could still be selected even when not highlighted. It now bails unless the candidate is a legal target.
- **Ability targeting used the wrong source.** `Field.execute_card_effect()` and `continue_skill_activation_after_mana()` requested targeting with the real field card (no `effect_kind`), so `cannot_be_chosen` never applied to abilities. Targeting now passes an explicit `source_kind` (`"Ability"` for skills/triggers, `"Summon"` for summons) through `request_target → set_viable_targets/has_viable_target → _card_matches_criteria → can_be_chosen_by`.

- **Break on equal damage.** `Card.is_broken()` used a strict `>` comparison, so a Forward with damage exactly equal to its power (e.g. 4000 damage on a 4000-power Forward) survived instead of breaking. Now uses `accumulated_damage >= power`.
- **Parse error:** `var effect_card := create_card(...)` could not infer a type because `create_card()` had no return type. Fixed with explicit `Card` typing; `create_card()` now declares `-> Card`.
- **Parse error:** `var modal_mode := (...)` in `assistant.gd` could not infer from a parenthesized boolean expression. Now `var modal_mode: bool`.
- **Latent parse error:** `var parts := []` in `scripts/ManaCost.gd` now uses explicit `Array` typing.
- **Attack declaration step stuck.** `show_pass_priority_button()` hid the pass button in `ATTACKING` mode, but the attack step runs a priority window right after the attack button. Pass button now hides only during modal modes (`PAYING_COST`, `TARGET`, `CHOOSE_CARD_IN_HAND`, `NO_PRIORITY`).
- **Assistant null `hand` reference.** `@onready var hand` pointed at `Game/Hand` instead of `Game/Player/Hand`, crashing `_ready()` once the choose-card signal was connected.
- **Life display not updating after damage.** `suffer_damage()` / `take_damage()` now call `powerLife.changeLife()`.
- **Power/life count animation not triggering.** `power_display.gd: changeLife()` rewritten to tween to the new value (`animate_life_change()` / `update_life_display()`), and the initial text now reads `power/life`.
- **Choose-card selection leak.** `hand.begin_choose_card()` now clears any previous selection crystal before starting a new one.
- **JSON trailing comma** in the Auron `"1"` entry removed (strict parser fix).

### Changed

- Debug setup in `scripts/game.gd`: Zack (12) is on the player's field at start; Aerith (64) and Evoker (68, Wind mana source) are in the opening hand for testing.
- **Break rule rewritten.** A Forward breaks when its accumulated damage is equal to or greater than its current power. (An earlier revision of this change used strict "greater than", which wrongly let a Forward with damage exactly equal to its power survive — corrected to `>=`.)
- **Power 0 is now a distinct removal event.** A Forward whose power reaches 0 or less is put into the Graveyard rather than "broken": `when_enter_break_from_field` does not trigger and `unbreakable` does not protect it. Both paths land in the existing Graveyard container (the Break Zone and Graveyard are the same zone in FF TCG), but the events are distinct.
- **State-based actions run more often.** `enforce_game_state_rules()` is now called after effect instructions finish (`Game._process_next_instruction()`) and after `damage_forward()`, not only in a combat clash, so effect damage (e.g. Ifrit, Zack's ETB) can break a Forward.
- **Card label text.** `power_display.gd` now shows `power/accumulated_damage` instead of `power/life`. `changeLife()` / `animate_life_change()` / `update_life_display()` renamed to `changeAccumulatedDamage()` / `animate_accumulated_damage_change()` / `update_accumulated_damage_display()`; `Card.powerLife` renamed to `Card.power_label`.
- **End Phase cleanup.** `Field.end_phase_cleanup()` → `Card.turn_end()` removes all accumulated damage from every card on the field and expires "until end of turn" status effects / power modifiers. (Runs immediately on entering the phase; see Known Issues re: end-of-turn abilities.)

### Known Issues / Unfinished Work

- **Power-reduction effects do not re-check state-based actions yet.** A negative `power_change()` can drive a card to 0 power without `enforce_game_state_rules()` running immediately (it is picked up the next time instructions finish or a clash occurs). `Card` has no reference back to `Game`, so this needs a callback or a field-level check.
- **`unbreakable` does not stop power-0 removal** — by design, since power 0 is not a break. (`card_effects.json` `"32"` is Chemist 1-032C, a 0-power Backup whose ETB grants `unbreakable` to a Forward.) Note that Backups store `"power": "0"` in the card database, so the zero-power / breakable scans deliberately look at `front_cards` only; scanning all cards would delete every Backup.
- **End-of-turn abilities have no window before cleanup.** `END_PHASE` runs `Field.end_phase_cleanup()` immediately; there is no priority round for "at the end of the turn / until end of turn" auto-abilities to resolve first (as the real End Phase requires). Needs a priority window in `_enter_phase(END_PHASE)` once such abilities exist.
- **Planet Protector's effect is not implemented.** Aerith's S-ability entry has an empty `instructions` array; the S + dull cost flow works, but activating all Forwards / protection from Summons and abilities is not scripted yet.
- **`activated_ability` keyword is not wired.** Card 8 in `assets/card_effects.json` uses `activated_ability`, but the field flow only activates `"skill"`. Either rename the key to `"skill"` or extend `try_activate_from_field()`.
- **Opponent turn switching is a TODO.** `next_phase()` prints "Turn completed" but does not flip `turn_owner`; opponent untap/draw/AI are not implemented.
- **Legacy dead code remains:** `scripts/ManaCost.gd` (live path uses a plain Dictionary), `stack.process_next_effect()`, and `game.pop_stack()` / `stack.pop_stack()`. Kept intentionally in case they are unfinished work.
- **`card_effects.json` coverage is still tiny** compared to the card database. The instruction system, choose-card system, conditional power, and S-cost data are ready for more entries.

## [Unreleased] — 2026-09-10

### Fixed

#### Rendering / Lighting
- **Scene rendered completely dark after upgrading from Godot 4.4 to 4.7.**
  - `game.tscn`: `DirectionalLight3D.light_cull_mask` changed from `4294966276` to `4294967295`. The old mask excluded layers 1–2 while every object uses the default layer 1. Godot 4.7's Compatibility renderer now respects directional light cull masks, so the light stopped affecting the whole scene.
  - `game.tscn`: added `ambient_light_source = 2` (color) and raised `ambient_light_energy` from `0.0` to `0.3` for soft fill light. Shadows and downward-facing surfaces are no longer pure black.

#### Priority System
- **Fixed detached coroutines from un-awaited recursion.** `priority()` in `scripts/game.gd` was calling itself without `await`, so the phase flow continued while a new priority round ran detached.
- **Fixed overlapping priority loops.** Added `_priority_lock` re-entrancy guard in `scripts/game.gd`. Extra `Stack.request_priority` signals during a running round are now no-ops; the running loop picks up the stack growth.
- **Priority order now uses `turn_owner`** instead of hardcoded player-first order. Turn switching itself is still a TODO until the opponent turn exists.
- **Fixed `DRAW_PHASE` stall.** `_enter_phase(DRAW_PHASE)` now calls `next_phase()` after drawing; previously the game stopped there.

#### Stack / Card Effects
- **Fixed Summon casting.** `stack.gd: cast_card()` no longer leaves Summons stuck on the stack. Summons now resolve with the `when_cast` keyword and are sent to their controller's graveyard after resolution.
- **Fixed `is_effect_card()` always returning true.** It compared a `String` to `null`, which caused cancelled hand casts to be `queue_free()`d. It now returns `key_word_effect != ""`.
- **Fixed aura crash at end of turn.** Aura power modifiers were stored with `null` duration and `turn_end()` did arithmetic on `null`. Auras now use duration `-1` (permanent), and `turn_end()` handles permanent modifiers.
- **Fixed signal arity mismatch.** `Card.declare_blocker()` emitted `execute_instructions` with two arguments on a one-argument signal.
- **Fixed missing targeting method.** Added `Card.is_cost_lower_than()` used by card 8's targeting data.
- **Fixed missing instruction method.** Added `game.damage_player()` used by card 53's break effect data.
- **Wired `when_enter_break_from_field`.** `game.break_card()` now triggers break-zone effects before the card leaves the field.
- **Effect copies now use the source card's controller** instead of hardcoded `'player'`.
- **Implemented proper Summon casting flow.**
  - `stack.gd`: when dragged, the Summon is parked visually on the stack while the cost is paid (`summon_casting_card` state), then target selection happens, and only after the target is confirmed does the card legally enter the stack list with `key_word_effect = "when_cast"`.
  - `scripts/hand.gd: charge()`: a Summon that requires a target cannot be cast unless at least one legal target exists on the field (`field.has_viable_target()`).
  - Mana payment is deferred until the target is confirmed: cancelling during target selection returns the Summon to hand and refunds all mana (nothing is discarded or tapped).
  - Resolved Summons go to their controller's graveyard.
- **Added Ifrit (1-004C).** `assets/card_effects.json` now has `"4": { "when_cast": ... }` — choose a Forward, deal it 4000 damage.
- **Fixed invalid trailing comma in `assets/card_effects.json`** (strict JSON parsers rejected the `"8"` entry).

#### Instruction Executor
- **Silent failures are now loud.** `_process_next_instruction()` and `_resolve_executor()` in `scripts/game.gd` now `push_error()` for unknown executors, unknown actions, and missing targets, then continue to the next instruction.
- **Targeting validation.** `battle_field.gd: set_viable_targets()` now errors if a criteria method does not exist on `Card`.

#### Data Loading
- **`CardDatabase.load_card_effects()` now checks the file exists** before opening it, matching the card database loader.
- **Removed debug prints** (`amanda`, `AmandaXXX`, `lala`, `andre`) from `CardDatabase.gd` and `game.gd`.

### Changed

- `scripts/game.gd: priority()` rewritten as a single non-recursive `while` loop:
  - Turn owner gets priority first, then the other player.
  - Stack growth during a window restarts the round.
  - Both players passing resolves the top stack effect, then priority resumes for the next item.
  - Both players passing on an empty stack advances the phase.
- `scripts/game.gd: next_phase()` rewritten with `match` for the combat step skips (no attacker → skip to Second Main; damage resolution → loop back to Attack Preparation).
- `stack.gd: stack_length()` now declares `-> int`.
- `scripts/card.gd: show_actions()` no longer spawns a broken "Attack" button that only tapped the card. Attacking is handled by the `ATTACK_DECLARATION_STEP` flow.
- `scripts/card.gd: turn_end()` iterates status effects safely and supports permanent power modifiers.
- `scripts/card.gd: is_tapped()` / `check_controller()` now accept either plain values or arrays for targeting criteria.

### Removed

- `card_in_field.gd` and `card_in_field.gd.uid` — unreferenced duplicate of `scripts/card.gd`.
- `scripts/TargetCriteria.gd` and `scripts/TargetCriteria.gd.uid` — unreferenced copy of `Instruction`.

### Known Issues / Unfinished Work

- **Summon effects need data.** Summons resolve through the new `when_cast` keyword, but `assets/card_effects.json` has no `when_cast` entries yet. Add `"when_cast": { "instructions": [...] }` per summon ID to make them do something.
- **`activated_ability` keyword is not wired.** Card 8 in `assets/card_effects.json` uses `activated_ability`, but the field flow only activates `"skill"`. Either rename the key to `"skill"` or extend `try_activate_from_field()`.
- **Opponent turn switching is a TODO.** `next_phase()` prints "Turn completed" but does not flip `turn_owner`; opponent untap/draw/AI are not implemented.
- **Legacy dead code remains:** `scripts/ManaCost.gd` (live path uses a plain Dictionary), `stack.process_next_effect()`, and `game.pop_stack()` / `stack.pop_stack()`. Kept intentionally in case they are unfinished work.
- **`card_effects.json` coverage is tiny** (7 cards) compared to the 3,644-card database. The instruction system is ready for more data.
