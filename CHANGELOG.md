# Changelog

All notable changes to the FF TCG Simulator project.

## [Unreleased] — 2026-09-11

**Session summary.** Started from "there is no scene routing, no opponent turns, and no way to win a game". Now: a menu boots into a configurable match; turns alternate; both sides act through an `Agent` seam (human UI today, AI today, a networked player later); the AI plays cards, attacks with tap-economy judgement and blocks; the human can block; and a match ends at 7 damage. The biggest structural win was separating "parked" (awaiting its cost) from "legally on the stack" — that conflation was the root of a whole class of bugs. Along the way the `GlobalVariables` god-object was reduced to presentation state + input mode, and the leftover editor junk was swept out.

### Next Steps (suggested order)

1. **Shuffle + seed.** `MatchSetup` carries `seed` / `shuffle` keys that nothing consumes, so every match opens identically. Apply a seeded shuffle when the decks are built; the seed is also the prerequisite for reproducible AI tests.
2. **Let the AI cast Summons.** `AIAgent._is_safe_to_play()` refuses them because the non-local targeting path (`Field.request_target()` → `Agent.choose_target()`) has never actually executed. Exercise it deliberately — Hades in the `"ai"` preset costs 5 and is unreachable, so the preset (or a dev key) needs an affordable Summon first.
3. **Reveal timing.** A parked card is face-up, so the opponent's play is visible before its cost is paid. Now that "parked" is an explicit state this is contained: render a parked card face-down for a non-local owner until it is committed.
4. **`DRAW_PHASE` on an empty deck should be a loss**, matching how `take_damage()` already reports running out of deck. Unreachable in practice (7 damage lands first), but it is a silent `return` of exactly the kind that has already caused bugs here.
5. **Per-combat resets are ambiguous.** `reset_attacker()` / `reset_blocker()` run after the phase they advanced into (see AGENTS.md), so the blocker arm re-resets at its start. Worth restructuring so the reset has one unambiguous moment — and `reset_attacker()` also never clears `set_attacker_status(true)`'s `'attacking'` flag / z-offset, unlike the guarded `reset_blocker()`.
6. **Richer card effects.** `activated_ability` in `card_effects.json` is unwired, `END_PHASE` has no priority window (so end-of-turn auto-abilities can't resolve before cleanup), and `card_effects.json` still covers only a handful of cards.
7. **State-refactor step 3** — replace the remaining `Player_Mode` comparisons with capability queries, and add a `phase_changed` signal so readers subscribe instead of sampling.

### Added

#### Opponent AI (Phase 3, first pass)
- `AIAgent.decide_attacker()` — tap-economy judgement. Attacking taps a Forward, so it cannot block on the opponent's next turn: the AI reserves a blocker (cheapest Forward that can still beat the opponent's best untapped Forward, else its strongest) and attacks with the strongest remaining Forward that does not trade down — strictly smaller than their best is skipped, equal power is allowed as an even trade.
- `AIAgent.decide_blocker()` — blocks only with a strictly bigger untapped Forward (equal power breaks both), preferring the smallest such card. Blocking is then free: the blocker takes less damage than its own power, and the attacker breaks.
- `AIAgent.choose_target()` — picks the strongest legal target (groundwork for Summons; still unreachable, see Known Issues).
- **The AI now plays cards.** `AIAgent.take_priority()` plays an affordable card from its hand during its own main phases.
- **Matches can now end.** `PlayerSide` exposes `damage_count()` / `is_defeated()` and emits `damaged(self)` from `take_damage()`; `Game` listens (via `game.tscn`, both `Player` and `Opponent`) and calls `_end_match()` at `DEFEAT_DAMAGE` (7) cards in the damage zone, or when the deck cannot supply the cards for the damage. `_end_match()` sets `match_over` — checked by `next_phase()`, so the phase machine stops — writes the result to `$PhaseText` and returns to the menu. Because the check hangs off the signal, every damage source (attacks and effects) is covered without touching the call sites.
- **The human can block.** New `Player_Mode.BLOCKING`: during `BLOCKER_DECLARATION` the local defender clicks their own untapped Forwards to select one (highlighted via the new `Card.set_blocker_status()`) and a `Block` / `No Block` button ends the declaration. `LocalAgent.decide_blocker()` returns `Field.blocker_card`, so the existing `declare_blocker()` → clash path is reused unchanged. The mode is pushed only for a local defender, and `Game._on_field_blocker_changed()` is gated on it — `blocker_changed` fires for both sides, exactly like `attacker_changed`.
- `Agent` gained `pay_cost()` (return whether a cost is covered) plus `choose_target()` / `choose_card_in_hand()` — the "drive the UI" seam, where a non-local agent performs the clicks a human would have made and the existing signal continuation carries on. `Field.request_target()` delegates to it for non-local owners so targeting can never leave the turn waiting for a click.
- `Game.play_card_for(player_id, card)` — plays from any hand: charges the card, has non-local owners pay via `Agent.pay_cost()`, then completes the payment itself with the human's modal buttons hidden.
- `Field.get_front_cards_for()` / `get_back_cards_for(controller)` — read accessors so agents don't reach into the raw arrays.
- `MatchSetup`'s `"ai"` preset now gives the opponent three mana sources and a playable hand (the debug board left it 1 untapped Backup, so it could never afford anything); the menu lists it first.
- Fixed: `Stack.cast_card()` played opponent cards onto the *local* player's field — `Field.play_card()` defaults to the local side, so `is_opponent` must be passed explicitly.

#### Opponent Turns + Agent Seam (Phase 2)
- `scripts/agents/agent.gd` (`Agent`) — decision seam: `take_priority()`, `decide_attacker()`, `decide_blocker()`. Base methods are coroutines (`_settle()`), so callers can `await` the seam uniformly for local, AI or future networked players.
- `LocalAgent` (human: pass button + attacker clicks), `MockAgent` (passes after a delay, never attacks/blocks), `AIAgent` (Phase 3 stub extending `MockAgent`).
- `Game.agent_for(player_id)` / `controller_for()` / `side_for()`; agents are bound in `start_match()` from `config["opponent_type"]` (`"mock"` default, `"ai"` supported).
- `Field.untap_cards_for(controller)` — Active Phase now untaps only the turn player's cards.
- Phase label shows the turn owner (`FIRST_MAIN_PHASE — P2`).

#### Menu + Match Setup (Phase 1)
- `main_menu.tscn` + `scripts/main_menu.gd` — entry point; UI built in code (Standard Match / Practice Board / Quit).
- `scripts/match_setup.gd` autoload `MatchSetup` — presets (`standard`, `debug`), pending `config`, `start_match(preset, overrides)`, `go_to_menu()`, `resolve_config()`.
- `Game.start_match(config)` — the hardcoded debug board moved out of `_ready()`; decks, hands, pre-placed field cards and the starting phase now come from config. Keys `opponent_type`, `seed` and `shuffle` are reserved for the AI/shuffle work.
- `Esc` in a match returns to the menu (only while no modal is mid-resolution).

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

- **A card awaiting its cost is only *parked*, not on the stack.** `Stack` now separates "parked" (a visual placeholder while the cost is being paid: `Stack.park_card()`, referenced by `casting_card` / `summon_casting_card`) from `Stack.cards` ("legally on the stack"). `_on_hand_charge_start()` no longer calls `add_card_to_tree()`, so a character card (Forward/Backup) **never** enters `cards` — `cast_card()` plays it straight to the field and there is nothing to pop. Only a Summon becomes a stack object, at `_commit_summon_to_stack()` after payment + target. Stacked on the earlier bug: `Stack._on_assistant_charge_cancelled()` used to pop a real card off `cards` and leave it parented to the Stack (frozen on screen). `game.tscn` also now wires `Opponent/Hand` to Assistant's `charge_cancelled` / `charge_complete` / `target_cancel` / `selected_cards_for_mana_has_changed` — without `charge_cancelled` a cancelled payment could not be returned to hand at all. And `AIAgent.take_priority()` gained a cheap `_can_afford()` total-mana check so it no longer starts payments it cannot finish. Side effect: `stack_length()` (which the priority loop uses to tell whether an action happened) is no longer inflated during a payment window. Layout follows the same split: `Stack.layout_cards()` (= `cards` + the parked card) is what `calculate_total_width()` / `update_card_positions()` read, because deriving the row from `cards` alone left the parked card out of the width and offset every card — which is why a card awaiting payment sat visibly off-centre. `_on_assistant_charge_complete()` re-lays out once the parked card leaves for the field.
- **`Card.reset()` crashed when a card had no mana crystal.** The "selected as a mana source" marker (`crystal_instance`) was created *only* by the two click handlers in `field_card_state.gd` / `hand_card_state.gd`. A card selected any other way — e.g. `AIAgent.pay_cost()` tapping Backups straight through `Field.add_card_to_mana_conversion()` — had a null crystal, and `reset()` (run on every payment completion) dereferenced it: `Invalid call. Nonexistent function 'queue_free' in base 'Nil'`. The marker now belongs to the `Card` (`show_mana_crystal()` / `clear_mana_crystal()`, both null-safe), `Field` / `Hand.add_card_to_mana_conversion()` create it, `remove_*` / `reset()` clear it, and the click handlers no longer touch `crystal_instance` directly — one creation site for the human and for agents.
- **Player damage went to the wrong player.** `Game.cause_damage()` unconditionally damaged `opponent`, which was only correct while the human always took the turn. Now damages `side_for(3 - turn_owner)`, so an opponent attack actually hits the human (and `side_for()` is used instead of sitting idle).
- **Blocking never worked end to end.** `Card.declare_blocker()` emitted `clash_attacker_blocker` immediately, and `Game._clean_instruction_stack()` then nulled `_current_blocker_card` before `DAMAGE_RESOLUTION` read it — so a declared block would clash twice *and* still count as unblocked. Now `declare_blocker()` only records the blocker, persisted as `Field.blocker_card` (which survives instruction cleanup), and the single clash happens in `DAMAGE_RESOLUTION`. `clash_attacker_blocker()` / `cause_attacking_damage()` read `Field.blocker_card` too.
- **An Attack button appeared during the opponent's turn.** `Field.attacker_changed` fires for the opponent's attacker as well (both sides share one `Field`), and `Game._on_field_attacker_changed()` offered the human a button for it. It now returns early unless `player_mode == ATTACKING`, i.e. only while the human's own declaration is open.

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

- Debug setup is now the `debug` preset in `MatchSetup`: Zack (12) on the player's field; Aerith (64) and Evoker (68, Wind mana source) in the opening hand; Zidane (71) on the opponent's field for the protection test.
- **Break rule rewritten.** A Forward breaks when its accumulated damage is equal to or greater than its current power. (An earlier revision of this change used strict "greater than", which wrongly let a Forward with damage exactly equal to its power survive — corrected to `>=`.)
- **Power 0 is now a distinct removal event.** A Forward whose power reaches 0 or less is put into the Graveyard rather than "broken": `when_enter_break_from_field` does not trigger and `unbreakable` does not protect it. Both paths land in the existing Graveyard container (the Break Zone and Graveyard are the same zone in FF TCG), but the events are distinct.
- **State-based actions run more often.** `enforce_game_state_rules()` is now called after effect instructions finish (`Game._process_next_instruction()`) and after `damage_forward()`, not only in a combat clash, so effect damage (e.g. Ifrit, Zack's ETB) can break a Forward.
- **Card label text.** `power_display.gd` now shows `power/accumulated_damage` instead of `power/life`. `changeLife()` / `animate_life_change()` / `update_life_display()` renamed to `changeAccumulatedDamage()` / `animate_accumulated_damage_change()` / `update_accumulated_damage_display()`; `Card.powerLife` renamed to `Card.power_label`.
- **End Phase cleanup.** `Field.end_phase_cleanup()` → `Card.turn_end()` removes all accumulated damage from every card on the field and expires "until end of turn" status effects / power modifiers. (Runs immediately on entering the phase; see Known Issues re: end-of-turn abilities.)
- **Entry point.** `run/main_scene` is now `main_menu.tscn`; `game.tscn` is launched via `MatchSetup.start_match()`. Running `game.tscn` directly still works — it falls back to the `debug` preset.
- **Turns alternate.** `next_phase()` flips `turn_owner` at end of turn; ACTIVE untaps the turn owner's cards (`Field.untap_cards_for()`) and DRAW draws for the turn owner (with an empty-deck guard). Both players get priority each round, turn owner first.
- **Priority / attack / block go through the agent seam.** `priority()` calls `agent_for(holder).take_priority()`; ATTACK_DECLARATION asks the turn owner's agent; BLOCKER_DECLARATION asks the defender's agent. `MOCK_opponent_pass_piority()` and `TEST_blocker()` are no longer called.
- **Non-local attack declaration keeps the phase's default `INSTANT_SPEED_TIME`** rather than forcing `NO_PRIORITY`, so the other player still gets the pass button (setting `NO_PRIORITY` hides it and hangs the priority loop).
- **Single owner for match state (state refactor, step 1).** `Game` now owns `phase` and `priority_holder`; `GlobalVariables` keeps only the local input mode, the UI signals and the hand-layout constants, and `Field.phase` is a read-through getter to `Game.phase`. Removed `GlobalVariables.phase` / `priority_holder` / `set_phase()` / `set_priority_holder()` / `get_priority()`; replaced `phase_priority_map` with a const `PHASE_DEFAULT_MODE` + `default_mode_for()`; moved `reset_to_default_phase_player_mode()` to `Game`; deleted the unused `_on_game_phase_change()`; dropped the dead enum values `BLOCKED` and `PRIORITY`.
- **Input mode is now derived from a modal stack (state refactor, step 2).** `player_mode = modal stack top OR base mode`, where the base comes from the current phase. Added `GlobalVariables.push_modal()` / `pop_modal()` / `refresh_mode()` / `set_base_mode()` / `has_modal()` / `modal_top()` and **deleted `set_player_mode()`** — nothing assigns the mode directly anymore. `TARGET`, `PAYING_COST`, `CHOOSE_CARD_IN_HAND` and `ATTACKING` are all pushed/popped by the flow that opens them, so closing a modal simply reveals the base again; `Game.reset_to_default_phase_player_mode()` is gone (its callers either pop their modal or call `refresh_mode()`), and `stack.gd` no longer reaches up to `get_parent()`. The redundant per-phase `set_player_mode()` lines in `_enter_phase` (ACTIVE / FIRST_MAIN / ATTACK_PREPARATION) were removed since they duplicated the phase default.

### Removed

- **Warning sweep.** Cleared every editor warning that was reported: unused private var `GlobalVariables._card_height`; `Assistant.show_choose_card_buttons()`'s `confirm_text`/`cancel_text` params renamed to `p_confirm_text`/`p_cancel_text` so they stop shadowing the class members; `AIAgent.pay_cost()`'s unused `cost` param → `_cost`; unused `var instructions` in `HandCardState.handle_grabbed()`; and `preload("res://Card.tscn")` → `"res://card.tscn"` in `game.gd` / `stack.gd` (the file on disk is lowercase, so exports would have failed).
- **Editor temp files.** Deleted 17 stale `<scene>.tmp` atomic-save leftovers from the project root (`card.tscn*.tmp`, `game.tscn*.tmp`) — they were months old and only cluttered Godot's project scan.
- **Unreferenced leftovers.** Deleted `mana_orb.tscn` (its two `res://Particles/...` textures no longer exist — the folder is gone), plus `capsule.tscn` / `sub_viewport.gd` / `sub_viewport.gd.uid`. `sub_viewport.gd` was a debug tool that saved a screenshot to `res://Font/confirm_text.png` at `_ready()`, which would fail in an exported build (`res://` is read-only). Nothing referenced any of the three by path *or* by `uid://`.

### Known Issues / Unfinished Work

- **The AI has no long-term plan.** It plays the first affordable card it sees (no plan beyond mana), skips Summons and any card whose enter-the-field effect needs a target (the non-local targeting path is untested), and never blocks an equal-power attacker (an even trade is declined rather than evaluated). The human's blocking is unrestricted by comparison — any untapped Forward may block, even one that would break.
- **`choose_card_in_hand()` is not wired to anything yet.** `Game._resolve_may_play_for_free()` and `Stack.begin_s_cost_selection()` still own the choose-card modal directly; a non-local agent would need those routed through the seam.
- **Decks are not shuffled.** `MatchSetup` carries `seed` / `shuffle` keys but neither is wired, so every match plays out the same opening; the seed is also needed for reproducible AI tests. `DRAW_PHASE` also still silently skips the draw on an empty deck rather than treating it as the loss it is (`take_damage()` does report running out of deck, so only the draw case is unwired).
- **Power-reduction effects do not re-check state-based actions yet.** A negative `power_change()` can drive a card to 0 power without `enforce_game_state_rules()` running immediately (it is picked up the next time instructions finish or a clash occurs). `Card` has no reference back to `Game`, so this needs a callback or a field-level check.
- **`unbreakable` does not stop power-0 removal** — by design, since power 0 is not a break. (`card_effects.json` `"32"` is Chemist 1-032C, a 0-power Backup whose ETB grants `unbreakable` to a Forward.) Note that Backups store `"power": "0"` in the card database, so the zero-power / breakable scans deliberately look at `front_cards` only; scanning all cards would delete every Backup.
- **End-of-turn abilities have no window before cleanup.** `END_PHASE` runs `Field.end_phase_cleanup()` immediately; there is no priority round for "at the end of the turn / until end of turn" auto-abilities to resolve first (as the real End Phase requires). Needs a priority window in `_enter_phase(END_PHASE)` once such abilities exist.
- **Planet Protector's effect is not implemented.** Aerith's S-ability entry has an empty `instructions` array; the S + dull cost flow works, but activating all Forwards / protection from Summons and abilities is not scripted yet.
- **`activated_ability` keyword is not wired.** Card 8 in `assets/card_effects.json` uses `activated_ability`, but the field flow only activates `"skill"`. Either rename the key to `"skill"` or extend `try_activate_from_field()`.
- **Legacy dead code remains:** `scripts/ManaCost.gd` (live path uses a plain Dictionary), `stack.process_next_effect()`, and `game.pop_stack()` / `stack.pop_stack()`. Since Phase 2 these are also unused: `game.MOCK_opponent_pass_piority()`, `game.TEST_blocker()` / `pass_priority()`, `field.untap_all_cards()`. Kept intentionally in case they are unfinished work.
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
