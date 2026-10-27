# AGENTS.md — FF TCG Simulator (Repository Guidelines)

Godot **4.7.2**, GDScript, GL Compatibility renderer. A 3D Final Fantasy TCG simulator.
Scenes: `main_menu.tscn` (main scene) → `game.tscn` (the match). Autoloads: `CardDatabase`, `GlobalVariables`, `MatchSetup` (`scripts/match_setup.gd`). A match is configured by `MatchSetup` before the scene change; `game.gd:_ready()` calls `start_match(MatchSetup.resolve_config())`, which falls back to the `debug` preset when `game.tscn` is run directly.

## Agent Rules (read first)

### Code-defined effects
- `scripts/effects/card_effect.gd` is the interface. A card subclass declares `handlers()` (event id -> Callable) and
  overrides only the hooks it uses; `EffectContext` carries the source, controller, event data and explicit helpers (`cards_in`,
  `choose`, `choose_targets`, `may`, `search_deck`, `reveal_top`, `mill`, `discard`, `damage`, `remove_from_game`).
  Effects are stateless and cached by `effect_registry.gd`.
- The registry is convention-based: a card's code effect lives at `assets/effects/card_<id>.gd` and is loaded on
  demand. Adding a card never means editing the registry.
- "Name an Element" goes through `Agent.choose_element`; `LocalAgent` opens `element_choice.tscn`, while AI/remote agents
  answer the same pull-shaped method. Temporary element replacement is the `element_override` status, read by
  `Card.current_elements()` before the printed element.
- A code hook wins over the JSON entry for the same event. Other events on the same card can remain JSON until they
  are migrated: this is a hybrid, not a flag day.
- Code triggers are stack objects. `Stack.enqueue_code_trigger()` stores the typed event id/payload on the copy;
  `Game._on_stack_execute_card_effect()` calls `CardEffect.dispatch()` with a fresh context when that copy resolves.
  Do not call an effect hook immediately when the event happens.
- `scripts/effects/events.gd` is the closed event vocabulary (`Event` + `NAMES`). A card declares triggers in
  `handlers()` exactly once: `function when_enter_field` is paired with
  `EVENTS.Event.ENTER_FIELD: Callable(self, "when_enter_field")`. The engine checks the map keys before enqueueing
  and dispatch() calls the matching Callable. Do not use `has_method(event)` for trigger detection.
- **Auto-abilities choose targets when they resolve.** In a `when_enter_field` / `when_attack` hook, call
  `await ctx.choose_targets(criteria, count)` and use the returned array. This matches the rules and lets each event
  have its own targeting logic.
- **Activated abilities and Summons choose targets before they are committed**, so their ability descriptors own
  target criteria and the hook receives `ctx.targets`. Do not move those choices into the resolution hook.
- Activated abilities use `AbilitySpec` (`scripts/effects/ability_spec.gd`) via `activated_abilities()` and
  `_ability(...)`: one object carries text, costs, target timing and the handler. Event hooks do not get this
  descriptor because a card has zero-or-one of each event. Code abilities win over JSON `skill` entries for that card.
- When inspecting an effect from a test, keep the effect object alive: `load(path).new().activated_abilities()` leaves
  the specs' `Callable`s pointing at a freed RefCounted. Store the effect in a local first.
- Targets are typed everywhere in card code: `CardQuery` says which cards, `TargetRequest` says domain/count, and
  `TargetSequence` says ordered stages. The same `CardQuery` is the filter argument for `cards_in`, Break Zone picks,
  hand plays, `search_deck`, `break_zone_to_hand`, and `untap_all_matching`; `named()` is exact and
  `name_contains()` is substring. Legacy dictionaries are converted at the engine boundary.
- A card's continuous power is `CardEffect.power_modifier(ctx)`, not a `power_per_rules` descriptor. It is called
  once per source per continuous scan, stored as `self_power:<id>`, and folded into the cached power by
  `Card.recompute_power()`. Dynamic properties use `CardEffect.properties(ctx)` and the same scan.
- `power_modifier()` and `properties()` must be read-only and must not read their own cached `power`.
- `CardEffect.modify_damage(ctx)` is a pure query returning the new amount; the default is identity.
  `Rules.modify_damage()` builds a `DamageContext` and scans every field card, so source-side,
  receiver-side and field-wide rules share one hook. Never add damage or mutate state inside it.
- `DamageContext.Kind` distinguishes combat, ability, Summon, EX BURST and generic effect damage;
  combat call sites pass COMBAT explicitly. Receiver-choice ordering is future work.
- Auras are `Aura` subclasses in `assets/effects/`, with a typed `CardQuery` and `KIND_POWER`/`KIND_STATUS`.
  The runtime bridge is `Aura.as_rule()`; the old `_aura({...})` descriptor is removed.
- Activated abilities are `CardAbility` subclasses in `assets/effects/`. Metadata is inherited from
  `AbilitySpec`; behaviour lives in `on_resolve(ctx)`, and `on_activation(ctx)` is the override point for cards
  that need to declare X or otherwise control activation.
- CP payment is EXACT (rules 11.2.2/11.2.2.2). Once `Assistant.payment_is_full()` is true, mana-card selection is
  ignored. The only overpay is one hand card producing 2 CP against a 1-CP gap.
- `assets/card_effects.json` no longer carries card entries. It is a
  `_definitions` reference only; every card effect lives under `assets/effects/card_<id>.gd`.
- Code-defined event triggers filter through `CardEffect.event_matches(event, source, data)` before a stack object
  is created; `card_left_field`, `summon_cast`, `damage_received` and similar shared events must not react to every
  instance. Once-per-turn triggers use `Card.claim_event_once(key, turn)`.
- Static protection and damage rule blocks are code-owned through `CardEffect.static_rules()`; `Card.static_rule()`
  is the single reader and falls back to JSON only while migration is incomplete.
- `power_per` rules are code-owned through `CardEffect.power_per_rules()`; the unified continuous scan reads code
  first and JSON only as fallback.
- Continuous state is refreshed by ONE `Field.refresh_continuous_effects()` pass over the field. Conditional power,
  power-per rules and auras all feed the same desired-grant ledger; do not add a separate full scan for a new family.
- `conditional_power` is a BOARD SCAN, not a registry. Scan the field at the continuous-effect invalidation
  points, keep a per-rule granted ledger for only the difference, and prune keys that disappear. Never poll per frame.
- Code abilities receive activation-time picks in `ctx.targets`; do not call `choose_targets()` again in the resolver.
- Yuffie-style "divide damage" abilities set `AbilitySpec.divide_total`, which makes the Stack choose the split before
  commit; the resolver applies it with `ctx.apply_damage_division()`.
- EX BURST is a pointer to an existing hook, not a separate effect. `CardEffect.ex_burst_event()` returns an
  `EVENTS.Event` id (`NONE` by default); `Card.ex_burst_event()` reads code first and translates a legacy JSON string
  only at the boundary.
- Printed keywords are code-owned through `CardEffect.keywords()`; `Card.has_code_keyword()` is the only reader.
  Add to that list rather than teaching each keyword getter a new source.
- `return_self` is a commit-time ability cost: the source can be in hand when the ability resolves, so never find Game
  by a fixed two-level parent walk. `Card.make_effect_context()` searches ancestors for the Game seam methods.
- Damage-to-player triggers must branch on `effect_handles_event()` before calling `begin_triggered_ability()`;
  the latter only knows JSON. Auron was the last target-dependent card blocked by this.
- Hand-play effects use `EffectContext.may_play_from_hand()`: shortlist, may, choose, play for free, optional dull.
- Summon targets are chosen BEFORE the Summon enters `Stack.cards`, and are stored on the Summon card itself in
  `effect_targets`. `_on_stack_execute_card_effect()` passes those same picks to `when_cast(ctx)`; do not re-target at
  resolution. `cast_targets()` is only a fallback for EX BURST, where no cast step happened.
- Mass return must START every `begin_return_card` tween before awaiting the first one. A plain sequential loop makes
  "return all Forwards" animate one card at a time.
- Code event conditions are resolved AFTER the trigger is queued. A broad `when_party_attack` code trigger can leave
  a stack object that later does nothing; tests should drain the stack, not equate one object with one effect.
- A code event opens its target session INSIDE its handler. `_on_stack_execute_card_effect` must not pre-clear
  targeting for `card.effect_event`, or it frees the arrow the handler just spawned. JSON/event-trigger paths still
  need the pre-clear because their target session was opened before resolution.
- Every trigger path that can carry a code event must go through `execute_card_effect`; Break Zone triggers and
  `when_chosen` originally checked only JSON and silently skipped code handlers.
- A code event with a broad trigger (206 `card_left_field`) may enqueue for an event its own filter later declines;
  test harnesses should drain the whole stack, not just the top object.
- Code ETBs are triggered abilities: `execute_card_effect` enqueues a stack object, and the handler resolves later.
  Probes must start stack resolution and wait for the target prompt or a settled no-target effect; do not assume the
  old synchronous JSON timing.
- `run_ex_burst` must allow a code event whose JSON keyword was already removed; the code handler is the effect.
- Costs are continuous queries: `CostContext` + `CardEffect.modify_cost()` (self) and `modify_cost_for()` (other),
  resolved by `Rules.effective_cost()`. Never mutate `Card.cost`; apply the minimum once after all modifiers.
- Auras are `AuraSpec`s returned by `CardEffect.auras()`, not ability specs and not events. `Field` owns the runtime
  grant and ledger; code auras win over JSON `aura` entries for that card. Aura definitions are continuous and must
  never be applied as permanent `power_change` deltas.
- Power is derived and cached: `base_power` + `_continuous_power` + `power_array` + `_manual_power_delta`.
  `recompute_power()` is the one normal writer of `power` and the one place the label changes. Continuous effects use
  `add_power_modifier(key, amount)` / `remove_power_modifier(key)`; do not add-and-deduct `power` directly.
- Test setup that needs a different printed power uses `set_base_power()`, not an assignment to the cached `power`.
- `Card.current_elements()` is a live query: printed `element` stays immutable, while `effect.current_elements(ctx,
  card)` may add or replace Elements. `is_element()` and every criteria/cost check must go through it.
- Keep class references by path (`preload("res://...")`) for new effect scripts; Godot's headless run does not have a
  fresh global `class_name` cache.

### Running Godot (harness only — allowed)
- **Three allowed invocations**, from the project root (all exit on their own; `--quit-after` is only a hang guard, and it counts FRAMES, so keep it generous — headless frames are fast):
  `"/c/Users/KABUM/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless res://tests/arrow_probe.tscn --quit-after 900`
  `"/c/Users/KABUM/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless res://tests/flow_probe.tscn --quit-after 5000`
  `"/c/Users/KABUM/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --headless res://tests/block_probe.tscn --quit-after 5000`
  Note the doubled path: `Downloads/Godot_v4.7.2-stable_win64.exe/` is a **directory** whose name ends in `.exe`, and the real binary is one level inside it. That ambiguity is exactly what made the first attempt fail. (The Desktop `Godot_v4.4` is the wrong version.)
- **`tests/arrow_probe.tscn`** — the arrow in isolation: 1 apex / 0 inflections, the measured peak against `peak_ratio`, the screen clamp, both mesh surfaces, the head's base sitting on the shaft's end, and the origin following a card. **`tests/flow_probe.tscn`** — boots the real `game.tscn` on the `debug` preset and drives the ETB → stack → targeting handoff: the effect copy landing on the stack, the arrow sourced from **that copy and not the field card**, exactly the legal targets marked, and the origin staying on the copy's top edge across the stack's 0.3 s tween. **`tests/block_probe.tscn`** — the blocking cues: the blue ring landing on exactly my untapped Forwards, the pick turning orange and drawing the arc centre-to-centre, a reselect moving both, the opponent's pick drawing the arc with no blue ring, and the cross-row arc staying a bow (`path < chord * 1.5`) rather than running along its own chord. All print a `RESULT:` line. **Extend these** rather than writing throwaway scripts, and add an assertion for every bug that gets fixed.
- **Never resolve a sibling through `get_tree().current_scene`** — it is only set when the game *is* the top-level scene, so a harness (or a second instance) gets **null** refs and the game runs half-wired. Walk the tree instead (`get_node("../../Field")`, `get_parent().get_node("Player/Hand")`). It also cannot be repaired from outside: assigning `current_scene` to a nested node is rejected (`p_scene->get_parent() != root`).
- Still forbidden: the editor; booting the full game just to "verify" something; and `--check-only` / `--script`, which do not load autoloads and therefore report `Identifier not found: CardDatabase / GlobalVariables` — actively misleading.
- **Discipline: two attempts on any invocation, then stop and report.** Do not iterate on command lines; that is what made the earlier attempt unproductive. Iterating on *code* and re-running is the point, and is not capped.
- Run it with the editor closed — a second instance can fight over the `.godot` import cache.
- Pre-existing harmless noise in every run: ~14x `Condition "!is_inside_tree()" is true. Returning: Transform3D()` (a node's global transform is read before it is parented). Anything else in the log is worth reading.

### Running Blender (allowed — it builds assets)
- Blender 4.4 is installed at `"C:/Program Files/Blender Foundation/Blender 4.4/blender.exe"` (not on PATH; the repo's `.blend` files are v404). It runs headless, so a mesh can be generated and rendered with no viewport in the loop:
  `"<blender>" --background --python "C:/…/Blender/build_gem_button.py"`
- `Blender/build_gem_button.py` is the parametric generator for the button: every dimension is a named constant at the top, and it writes `gem_button.glb` (for Godot), `gem_button.blend` (to hand-edit) and two Cycles previews.
- **The workflow is render → LOOK at the PNG → fix.** The assistant cannot see a viewport, but it can render and then read the image — and that is what caught all three of the button's errors (a stone hidden inside a solid plate, spikes from a wrong offset, and a light card photographed instead of the subject). Do not tune a material blind when a render is one command away.
- Lessons that generalise: **lights are for reflections, not illumination.** A polished surface mirrors its environment, so the bright source has to sit where the surface's reflection points, and a light placed in front of the subject is invisible to it — worse, if it is between the camera and the subject, it *is* the photograph. Large emissive cards placed **outside the camera's frustum** give chrome its bright/dark bands. And **offset a shape exactly, never per-point radially**: `stadium(hw+d, hh+d)` is the exact outward offset of `stadium(hw, hh)`, whereas pushing each point along its own radius is only correct on the caps and folds the straights.
- **Replacing a scene that other scenes instance: keep every node path identical.** Saved instance overrides resolve by path, so a renamed or missing node silently drops its override rather than erroring. `tests/button_probe.tscn` asserts the path sets match before such a swap (`BigButton has 9 node paths; missing from GemButton: []`).

### Context efficiency
- **Search before reading:** `grep` for the symbol first, then read only the surrounding lines.
- **Understand one function at a time:** read its definition and its immediate callers — not the entire file.
- **Debug narrowly:** read only the failing function and its direct dependencies.
- **Skip generated/vendored paths:** `addons/`, `.godot/`, and any `.import` / `.res` files, unless explicitly asked about assets.
- **The scripts are split across two folders:** `battle_field.gd`, `stack.gd`, `assistant.gd`, `power_display.gd` are at the **repo root**, while `game.gd`, `card.gd`, `hand.gd`, `player_side.gd` are in `scripts/`. `grep -r` for the filename rather than guessing a path — a wrong guess costs a round trip.
- **Warnings arrive in batches.** The user runs Godot and pastes the warning list (`UNUSED_*`, `SHADOWED_VARIABLE`, `Case mismatch …`). Fix every line, then sweep for the same *class* (`grep` for other unused private vars, other case-mismatched `res://` paths) instead of waiting for the next run.

## Rules Reference (vector DB)

The user maintains a vector database of the official FFTCG rules. Consult it before deciding a timing/priority/trigger question,
rather than inventing a rule:

```bash
"C:\Users\KABUM\Desktop\VectorDb\rag-env\Scripts\python.exe" "C:\Users\KABUM\Desktop\VectorDb\search.py" "your rules question"
```

Quote the returned page/rule when it changes an implementation decision. It currently contains the game rules (for example,
11.8.x auto-abilities: they go onto the stack at the next opportunity and can be responded to).

## Mill

`mill_player(player_id, count)` / `opponent_mills(count)` own the RULE; `Graveyard.draw(card)` owns the ANIMATION, and
the loops `await` it, so a mill N is N sequential flights (each flight 1.0 s, so ~3 s for a mill 3). Deck cards are children of
the Deck node, so the flight starts from the card's real global position; the card is reparented into the pile BEFORE
it moves, which is what makes it face-up at Break Zone size during the flight rather than popping at the end.

Knobs (per node, Inspector): `mill_seconds` 1.0, `mill_arc_height` 0.9 m, `mill_ease`.

## Abilities: one vocabulary, three costs

Every non-S ability is a `skill` entry. The differences are only in the cost keys:

  "cost": {"neutral": 2}        mana
  "tap": true                   dull as part of the cost
  "s_cost": true                discard a card with the same name (hand picker)
  "sacrifice": {"is_type":"Backup","controller":"player"}   put one of your cards into the Break Zone
  "sacrifice": {"is_source": true}                          put THIS card into the Break Zone (no picker)

Sacrifice is chosen by the OWNER through `Agent.choose_sacrifice()` (LocalAgent opens the card picker; the base agent
takes the cheapest) and is paid at activation. Aborting it clears the proxy. A skill whose sacrifice has no candidates
is not offered by `can_activate_now`, so the green ring and the picker agree.

## Targeting can have STAGES

`"choose_target"` may be a Dictionary (one stage) or an **Array of stages**, asked in order — Hades 52 is Forward
then Backup. `Field.targeting_blocks` holds them; `_begin_target_block(index)` starts one; a pick advances to the
next stage automatically, and Confirm appears only after the last.

`has_viable_target()` requires EVERY stage to have a legal candidate: mandatory targets are judged at cast time, so a
missing stage makes the card illegal to play.

Instructions address a stage with an index: `dull_targets(0)`, `return_targets_to_hand(1)`. `_selected_targets(index)`
is the single place that decides "all picks" (index < 0) or one pick. Add an index parameter to any new
target-instruction wrapper the same way.

The instruction chain is now awaitable: `_execute_instructions_and_wait()` waits for `instructions_finished`, which is
emitted only from the empty-queue branch. Do NOT treat an empty `_current_instructions` as finished — an instruction
that suspends on an animation or a modal empties the queue while it is still running. `_clean_instruction_stack()`
runs at that same chain end.

## Targeting has a DOMAIN: field or stack

`"choose_target": {"in": "stack", ...}` makes the session's candidates come from `Stack.cards` instead of the field.
`in` and `count` are SESSION keys — add them to `card_target.gd`'s `SESSION_KEYS` if you add more, or
`matches_criteria` will treat them as card predicates and refuse every candidate.

`Field._target_candidates()` is the one place that picks the list; `set_viable_targets` and `has_viable_target` both
go through it. A stack card's click reaches `StackCardState.handle_grabbed()`, which forwards to
`Field.set_target_card()` while the mode is TARGET and the card is legal.

CANCELLING a stack object is `Stack.cancel_stack_card()`: remove it from `cards` (so the priority loop never picks
it), then move it to its owner's Break Zone — it was paid for. Do NOT set a flag and let it resolve with no effect;
removal is what makes it never resolve.

## A zone picker is the deck search, not a new window

`DeckSearch.open(ids, filter, subtitle_text)` is reused for the Break Zone (Devout 48/77). Pass the zone label through
the subtitle; do not build a second viewer.

The choice goes through the agent seam (`Agent.choose_break_zone_card`), so a human gets the window and an AI/mock/remote
answers without one — an instruction awaiting a pick must never hang.

A card RETURNING from a non-field zone is a NEW permanent: call `Card.reset_for_field_arrival()`. It subtracts the
remaining `power_array` buffs from the running `power` before clearing them (clearing the list alone bakes the bonus
in), clears statuses and damage, untaps and unsets `broken`.

Per-ability time gates (`only_your_turn`) must be checked in BOTH `can_activate_now` and the multi-skill picker's
usable list, or the green ring and the picker disagree.

## "Chosen" is a targeting event, and it has rules

`Field.notify_targets_chosen()` is called from `Game._on_targets_confirmed` (Assistant.target_complete) — the moment a
session is CONFIRMED, not when rings are clicked. Three conditions:

* once per session (`_chosen_notified`, reset in `request_target`), because picks can be replaced before confirming;
* the chooser (`source_card.controller`) must differ from the card's controller — "chosen by your opponent";
* `targeting_source_kind` must be `Summon` or `Ability`. Set effects never choose, so they must not fire this (same
  line as `cannot_be_chosen`).

The connection is placed AFTER the Stack's `_on_assistant_target_complete` in `game.tscn` on purpose: the triggered
ability must land on top of the Summon/ability that caused it, so it resolves first.

## Cards 100-216 coverage

### Static entry rules are board queries

`on_character_enter` is read from `get_all_cards()` at the moment a Character enters (`Field._apply_entry_rules`).
Do NOT register a listener for it: a source that leaves the field stops being found automatically, which is exactly
the teardown-free behaviour we want. It is O(field) per entry; index it only if such rules become numerous.

### Unique names are checked before entry

`Field.play_card()` calls `Game.would_be_unique_name_conflict()` BEFORE reparenting. The card on the field is kept;
the new copy goes through `send_off_field_card_to_break_zone()` (`broken = false`, no enter-the-field trigger).
Setup (`animate == false`) is exempt. There is intentionally no SBA sweep: test boards place duplicate names on
purpose, and no current effect changes a name in place. Add one in `enforce_game_state_rules()` if that changes.

### Reveal staging

`Game.reveal_top(count)` pulls cards from the deck top, animates each one sequentially (lift, face-up, 0.5 s hold,
face-down again, 0.5 s hold), then calls `Card.set_hidden(true)` and stores the Card in `Game.revealed_cards`. The array is the
search domain for `choose_revealed`; `put_revealed_on_bottom` preserves reveal order. Use `Card.set_hidden(false)`
(or any `Card.enter_zone`, which now restores it) before moving a revealed card.

`check_revealed` writes the instruction latch. Put the two conditional branches IMMEDIATELY after it: the dispatcher
sets `_last_action_succeeded = true` before every other instruction, so an intervening instruction destroys the check.

### Silence status icon

`assets/icons/silence_balloon.svg` is one continuous path: white balloon, black outline and a joined tail with no
internal seam. It is imported at 2x with mipmaps; the three dots are separate `Sprite3D` nodes in
`scripts/silence_icon.gd`; do not put animation into the SVG.

The icon is a child of `Card`, shown only when `current_zone == FIELD` and `abilities_nullified` is present. Place it
using the CAMERA's screen axes, not card-local +x: field cards are rotated, and the same local axis can appear on
either screen side. The four-frame dot loop is 1, 2, 3, none; the empty beat matters. Balloon sprites need
`render_priority` below the dots, and dots need to be ordered by the screen axis, or transparent sorting/rotation makes
them appear hidden or shifted.

`tests/silence_icon_probe.tscn` verifies show/hide and the dot loop. For a visual check, run the shot harness with
`--scene res://tests/silence_preview.tscn --as-scene 1`.

### Ability nullification (Wakka 216)

`Card.card_effects` is a read-time view, not the raw printed data. While `status_effects` contains `abilities_nullified`
it returns an empty dictionary; `_printed_effects` holds the real data and comes back when the status expires. Do not
clear the shared JSON or mutate the printed effects.

Nullification must also be respected by things that registered earlier: `conditional_power`, `power_per`, auras,
party Brave and entry rules all check `abilities_enabled()`, and the applying instruction recomputes those systems.
Abilities already on the stack keep their proxy snapshots and still resolve.

Power setting uses `Card.set_power_value()`, a temporary `power_change` delta, so normal buff expiry still works.

### Copied skills (Kimahri 102)

A copied Special Ability lives in `Card.copied_skill` (one slot, empty = none). Do **not** append it to
`card_effects["skill"]`; use `Card.activation_skills()`, which is the single activation list (printed + copied). The
copy strips `cost`, `tap`, `s_cost`, `discard` and `sacrifice` but keeps `only_*` restrictions and all effect data.

The stack proxy snapshots the chosen definition in `skill_def_override`. That is required because an ability on the
stack is independent of its source: a later Ronso Rage may overwrite `copied_skill`, or Kimahri may leave the field,
while the already-activated copy is still resolving. `consume_copied_skill(token)` only clears the exact permission the
proxy was created from. `Copied_skill` clears on use, on leaving the field, and in `turn_end`.

### Discard flight

`Graveyard.discard(card)` appends the card to the pile FIRST and then tweens its visual from the hand to the assigned
slot. This is the opposite order from `Graveyard.draw()` on purpose: discard effects, S costs and probes must see the
card in the Break Zone immediately, while the player still sees it travel. Call it from `Hand.discard_card()` and
`Hand.send_selected_cards_to_graveyard()`; do not wait on the tween.

### Light/Dark and any-element mana

* Rule 7.7.5 normally allows one Light or Dark card per side. `Game.would_break_light_dark_limit()` is a board query
  called from `Field.play_card()` before entry. `light_dark_exempt` on Cosmos/Chaos lets them enter beside their own
  element and, while on the field, allows more of that element. Setup boards (`animate == false`) are exempt.
* `Card.mana_element()` returns `"any"` for a card with `produces_any_element` while it is on the field. Field/Hand
  mana emitters must use `mana_element()`, not `element`. `Assistant.payment_breakdown()` spends any-element mana on
  unmatched elemental points first, then on wild points.

### Delayed break and status payloads

* `break_at_end_of_turn` is a status resolved by `Field.end_phase_cleanup()` before `turn_end()` clears statuses.
* `add_status_to_targets(status, duration, payload)` stores the payload and automatically adds `source` and `controller`.
  `_trigger_status_break_zone_effects()` restores both while executing the payload's `on_enter_break_zone` instructions.
* The generic `Game.choose_target(criteria)` instruction opens a targeting session in an instruction chain and writes
  the picks to `_targets`, so following instructions can act on them.

### Conditional statuses

`conditional_status` is evaluated live from `if_controls`; use it instead of writing a status when the grant should
disappear as soon as the board changes (Tidus + Yuna).

### Board-wide events use the `triggers` array

`Card.card_effects["triggers"]` is an array of event watchers, separate from the printed `when_*` keywords:

* Events: `damage_received`, `card_left_field`, `summon_cast`, `forward_attacks`.
* `filter` is criteria on the event card from the trigger owner's perspective; `damage_received` has no card and only
  compares `controller`.
* `target` controls the default instruction target: `source` (default), `event` (the card in the event context), or
  `none`. `choose_target` replaces it with a targeting session.
* `once_per_turn` is keyed by card instance + trigger index + `Game.turn_number`, so no reset pass is needed.
* Dispatch points: `Game._on_player_side_damaged`, `Game._send_card_to_graveyard` (only when `current_zone` was FIELD
  before the move), `Stack.cast_card` for Summons, and `Field.execute_card_attack`.
* **A non-local agent finishes targeting inside `request_target()`.** `AIAgent.choose_target()` calls
  `set_target_card()` + `on_target_complete()` synchronously, so the signal is already spent when `request_target()`
  returns. Check `targeting_picked` first and only await `target_complete` when it is still empty; otherwise the
  trigger hangs forever.
* Event triggers are **triggered abilities and go on the stack**. `Field.trigger_event()` only matches and enqueues
  an effect copy; `Game._resolve_event_trigger()` does `may`, target selection and instructions at resolution. The
  priority loop therefore lets either player respond first. Do not resolve an event trigger inline.
* The optional Confirm/Refuse prompt pushes `OPTIONAL_CHOICE`; otherwise the pass-phase button can appear over it.
* Event-trigger resolution must end its targeting session. `Game._on_stack_execute_card_effect` calls
  `Field.finish_targeting_state()` before AND after `_resolve_event_trigger()`; without the second call the last locked
  arc and the orange pick ring outlive Cecil's effect.

### Costs are read through Rules.effective_cost only

Cost modifiers are board queries, not payment-time special cases:

* `self_cost.per` counts matching cards **controlled by the card's controller**; the card itself is excluded. Use it
  for “cost 1 less for each Category VII Forward you control”.
* `cost_aura` supports `for` (type), `name` (one card), `element` (e.g. Water Summons), and `from` (own/opponent).
* `min` is a final-cost floor for the modifier. It only limits how much that modifier removes; a cost already below
  the floor is not raised.
* The payment modal and the AI both call `effective_cost()`. Never add a second cost calculator.

187/213 currently carry only their cost piece in `card_effects.json` and remain in `NEEDS_CODE` until their other
abilities land.

### B3 rules: targeting priority, per-rule ledgers, owner-aware searches

* `must_be_chosen` is enforced in `Field.set_viable_targets`, not in `Card.can_be_chosen_by`: it is a property of the
  CHOICE SET (collapse legal candidates to the mandatory ones), not of a single candidate.
* `conditional_cannot_be_chosen` is a live `if_controls` board query on the card, evaluated by `controls_matching()`.
* `conditional_power` needs a `granted` ledger PER RULE. A single `current_conditional_bonus` makes the second rule
  overwrite the first (Rikku 201: Yuna and Paine must both stack).
* `search_deck(filter, destination, tapped)` is owner-aware and agent-driven. Destinations include `field` and
  `field_dull`; the search filter is bridged between CardFilter keys (`name`, `type`, `category`, `job`, `element`)
  and Card criteria (`is_named`, `is_type`, ...). Do not add another direct window call for a new search card.
* Two-player choices use generic instructions, not per-card Game functions. Cloud 158 is
  `choose_card(self)` -> `choose_card(opponent)` -> `apply_effect(..., exclude_chosen)` ->
  `put_targets_into_break_zone`; `choose_card` routes the pick through `Agent.choose_field_card`. Serafie 109 uses
  `choose_break_zone_card(self)` -> `choose_break_zone_card(opponent)` -> `put_card_into_hand`. Prefer composing these
  verbs over adding an `each_player_...` function.
* `only_if_damage_received` is a per-ability gate like `only_your_turn` / `only_if_blocking`. A `tap` cost alone asks
  `can_tap()`; a non-tap ability remains available while tapped and while summoning-sick.
* Return-to-hand checks `Card.can_be_returned_to_hand_by(source, kind)` at the single `return_targets_to_hand` verb.

### Damage modifiers: one pipeline, one context

`Rules.modify_damage()` is the only place damage is modified. It builds one typed `DamageContext` and asks every
field card's `CardEffect.modify_damage(ctx)` in turn; the default returns the amount unchanged. Source-side
(Warrior of Light), receiver-side (Knight) and field-wide (Minwu) rules all use this one pure hook. Context fields:
`amount`, `original_amount`, `source`, `source_controller`, `source_kind`, `target`, `kind`, `rule_owner`, `field`.
`DamageContext.Kind` distinguishes combat, ability, Summon, EX BURST and generic effect damage. Do not add damage or
mutate state inside `modify_damage()`.
Both `modify_damage(ctx: DAMAGE_CONTEXT)` and `prevents_break(ctx: BREAK_CONTEXT)` are typed through script
constants on `CardEffect`. Card subclasses inherit those constants and must not redeclare them (GDScript rejects a
child member with the same name).
Every card hook now types its context parameter too: `ctx: EFFECT_CONTEXT` for event hooks, ability hooks, power
and element queries; `ctx: COST_CONTEXT` for `modify_cost` / `modify_cost_for`; plus the damage and break contexts.
Card subclasses inherit these constants from `CardEffect` / `CardAbility`, so the type name is available without a
global `class_name` and without redeclaring the constant.

PENDING ONE-SHOT DAMAGE RULES are status payloads, not named flags. `add_status_effect(status, duration, payload)`
stores the payload; any status whose payload has `operation` and `value` is applied to damage dealt to that card. The
status name is only a label. `once` defaults to true; `once: false` keeps applying until `turn_end()` expires it. Do
not reintroduce a `next_damage_zero`-style boolean — use a payload such as
`{"operation": "set", "value": 0}` or `{"operation": "subtract", "value": 2000}`.

Do NOT add a direct `card.suffer_damage()` call anywhere: it bypasses modifiers. `divide_damage` and the party-to-blocker
hit were routed through `Field.cause_damage` for this reason.

### Multi-colour mana sources
- `Card.mana_elements()` is the payment UI's list. A `produces_any_element` source returns all eight CJK
  colours; any other source returns its live `current_elements()`.
- When that list has more than one entry, `Field.begin_mana_choice(card)` opens `mana_choice.tscn` — small
  `ManaCrystal` nodes in a camera-plane circle, static, hover-growing, click-to-choose. The chosen colour is
  stored in `Field.selected_mana_elements` so `remove_card_from_mana_conversion()` refunds exactly that colour.
  Do not re-derive a refund from `card.mana_element()` after a choice.
- `add_card_to_mana_conversion(card, element)` accepts the chosen element; `element == "any"` remains valid for
  agents/payment paths that deliberately produce wild CP.

### Break replacement: one context, one boolean

`Game.break_card()` asks `Rules.is_protected_from_break()`, which builds a `BreakContext` (`card` about to break,
`rule_owner`, typed `BreakCause`) and scans every field card's `CardEffect.prevents_break(ctx)`. The default returns
false; if any protector returns true the break is stopped. Only `break_card()` asks this question:
`put_card_into_graveyard()` is removal, not a break, and must bypass break protection. `unbreakable` remains a
separate status checked before the scan.

Yuna 176's `break_zone_exile` is auto-accepted (known simplification: the “may” would need an async pre-break step);
it is gated on `current_zone == FIELD`, so unique-name duplicates from hand/stack are not exiled.

`assets/card_effects.json` carries a top-level `_definitions` object documenting the context, modifier schema,
conditions, targets, triggers, skill fields, instructions and statuses. Update it when adding new vocabulary.

B1 introduced these primitives; use them rather than adding one-off code:

* `is_damaged` criteria; `discard_cards`; `break_zone_to_hand`; `look_top_may_bottom`; `put_hand_card_on_bottom`;
  `cast_summon_for_free`; `power_change_targets_if_blocking`; `only_if_blocking` (per ability); `self_cost` with
  `if_controls`; `double_power`; `set_extra_attacks` / `extra_attacks_from_damage`.
* Auras can `grant_status` (counted in `Card.granted_statuses`), and `unregister_card_auras` revokes exactly what it
  granted. Haste/Brave/First Strike all read printed + timed status + granted.


`python3 tools/coverage_range.py --check` must print `UNCLASSIFIED: 0`. The `NEEDS_CODE` dict in that tool is the
roadmap: an id moves out when its primitive lands, and an entry in `card_effects.json` always wins.

Data batches live in `tools/card_data_batches.py`; they append to the JSON without reformatting it. `tools/cards_range.py
<first> <last>` prints the raw card texts the batches are derived from.

When writing data, remember the two placement rules:

* `apply_effect` belongs at the **top level** of a trigger, or **inside the specific skill def** it applies to.
  Putting it top-level on a card that also has a choose_target trigger re-targets that trigger's instructions.
* Character `EX BURST` uses the SAME fake-stack copy as a Summon: `"ex_burst": "when_enter_field"` queues the ETB
  effect and resolves it immediately, leaving the body in the Damage Zone (a deliberate simplification of the official
  "play it for free"). `Game.run_ex_burst()` must resolve the queued effect in BOTH branches - a no-target burst that
  only queues would otherwise sit on the stack forever.

## Auditing call sites in game.gd

Run `python3 tools/dead_audit.py [file.gd]` (default scripts/game.gd), and `python3 tools/member_audit.py [file.gd]` for unused vars/consts. It reports each function as called / DATA-ONLY / TEST-ONLY / QUOTED-ONLY /
scene-connected / UNREFERENCED.

Two traps it exists to avoid:

* **Instruction handlers are DATA.** `damage_targets`, `draw_cards`, `break_targets`, ... have no `.gd` caller; they
  are dispatched by name from `assets/card_effects.json`. Search the JSON before declaring one dead.
* **A bare name is a call.** `tween_callback(_end_damage_zoom)` and `assistant.set_confirm_button(finish_target)` pass a
  Callable, which a "name(" search does not see.

The tool also checks `method="..."` scene connections, so `_on_*` handlers are only reported as connected when they
actually are.

## Signals are for events; commands are direct calls

Use a signal when something HAPPENED and zero-or-many listeners may react (`damaged`, `target_complete`,
`add_card_effect_to_stack`). Use a direct, named call when exactly one owner must do work and the caller needs it
ordered/awaited (`game.run_ex_burst(...)`).

Do NOT use `call("method", ...)` for a production command between nodes whose type is known: it is invisible to
autocomplete, rename and Find Usages. Keep `.call()` only for dynamically instantiated scenes whose type is unknown
(`window.call("open", ...)`). If the receiver has no `class_name` (Game does not), declare an untyped
`@onready var game = get_parent()` and call the method by name — that is enough for grep and Find Usages.

## EX BURST suppression is decided by the DAMAGE SOURCE

`PlayerSide.take_damage(amount, source)` threads the dealer into `_run_ex_burst(card, source)`; a source with
`ex_burst_disabler` (printed or status) skips the burst while the card still enters the Damage Zone. Rules paths that
damage a player must pass a source; only debug keys may omit it.

`DamageZone.draw()` must call `card.enter_zone(Card.Zone.DAMAGE)` — it is the animated path used for every real damage
card, and without it the card keeps its DECK zone/rotation.

## Element spellings live in scripts/elements.gd

ELEMENT NAMES / CJK / ACCENT and `key_to_element()` are static data in `scripts/elements.gd`, preloaded by path
(`const ELEMENTS := preload("res://scripts/elements.gd")`). The old ElementBadge scene and all its generated assets are
gone — do not reintroduce a class_name for this table, because a class_name added since Godot last scanned is not in the
headless cache.

When deleting a script, delete its `.uid` and check `.tscn` ext_resources and instanced nodes too: `godot --headless
res://game.tscn` will surface a dangling path immediately.

## "May" is an instruction flag, decided at resolution

`may: true` on an instruction makes the controller choose when the instruction is REACHED — after targets are locked,
which is the rule. `may_by: "opponent"` gives the choice to the other player (Leon 60); `may_prompt` is the confirm
button's text. A refusal skips the instruction, sets `_last_action_succeeded = false`, and the chain continues.

`LocalAgent.confirm_optional()` shows Confirm / Refuse through Assistant.show_modal. Answers live on members, not
lambdas — GDScript lambdas capture locals by value.

Block triggers are queued by `Game.set_blocker()`: the blocker's `when_blocks`, and `when_blocked` for EVERY attacking
party member. Declaration is the single moment both become true.

`play_from_hand` plays for free — no mana, no charge; call `Hand.remove_for_play()` and then
`Card.reset_for_field_arrival()` before `Field.play_card()`.

## Damage goes through Field.cause_damage

Do NOT call `card.suffer_damage()` for game damage. `Field.cause_damage(target, amount, source, kind, controller)`
applies `modify_damage`, lands the damage, and runs the dealer's `on_causing_damage_to_forward` riders. Every path
(effect damage, combat, first strike, party damage, blocker split) already uses it; a new damage path must too or
riders silently stop applying.

A status can be a DICTIONARY payload: `{duration, controller, on_enter_break_zone}`. `Card.turn_end()` expires it
like a number, and `Game.trigger_break_zone_keywords()` runs `on_enter_break_zone` once when the card reaches the
Break Zone FROM THE FIELD. It fires whether or not the card BROKE — the card text says "put from the field into the
Break Zone", so do not gate this on `broken`; `when_break` is the break-only keyword. Use this shape when a trigger has
to remember something about the card it is attached to (Cid 72/73's "the Forward that took damage from Cid").

## Rules live in scripts/rules.gd, not in Field

`Field.rules` owns the CONTINUOUS-EFFECT QUERIES (created in `Field._ready`, bound to the board, NO Game
reference): `effective_cost`, `modify_damage`,
`is_protected_from_being_chosen`, `is_protected_from_break`. Field keeps one-line forwarders so callers and probes are
unchanged. Registration and stateful ledgers (`_auras`, `_power_per_effects`, `_conditional_effects`) still live on
Field, because it is the only thing that knows when a card enters or leaves.

When adding a NEW rule, put the query in `scripts/rules.gd` and register/broadcast from Field. Do not add another
scan-and-answer method to `battle_field.gd`.


`Card.suffer_damage(damage, kind, controller, source_card)` records BOTH the cause (Summon/Ability/combat) and the
DEALING card. `Field.modify_damage(source, target, amount)` runs before the damage is applied (Warrior of Light
doubles to a cost-4+ Forward), so a doubled hit counts once for the break check. Combat passes the opposing card;
effect instructions pass `_current_source_card`.

A trigger whose `choose_target` has no legal candidate must NOT open a targeting session — `execute_card_effect`
checks `has_viable_target` first. Otherwise "you may deal 7000 to a dull Forward" with no dull Forward strands the
effect.

## power_per: continuous, count-based power


`power_per` (Jecht, Dark Knight, Gabranth) is the counted sibling of `conditional_power`. Each rule stores what it
currently GRANTS and applies only the difference — never recompute `power` from its base, or temporary buffs and auras
are erased. The count is read live: a criteria block counted over the board, or `"damage_received"` = the controller's
damage zone size.

Recompute points: `Field.play_card`, `Field.remove_card`, and `Game._on_player_side_damaged`. `brave_at` toggles Brave
on the same pass and tracks `brave_granted` so it only removes the status it put there.

JSON numbers are FLOATS: `{"氷": 1.0}` is not `==` to `{"氷": 1}` as a Dictionary. Compare `int(...)` of the value.

## Costs Are a Board Question

`Card.get_cost()` is the PRINTED cost. The cost actually paid is `Field.effective_cost(card)`: printed plus every
matching `"cost_aura": {"for": "Summon", "from": "opponent", "delta": 1}`, applied to the neutral part and floored at 0
(so a negative delta is a reduction).

There are exactly TWO readers and they must agree: `Assistant._on_hand_charge_start` (sets `mana_cost`, which drives
the crystal row, `remaining_cost`, `can_pay_cost`, `pay_cost`) and `AIAgent._can_afford`. If you add a third cost
reader — a new agent, a preview — it must call `effective_cost()` too, or it will believe a surcharged Summon is cheap.

Cost is LOCKED when the payment opens; a modifier leaving the field mid-payment does not refund.

## Choice Shields (Dajh, Serah)

A "cannot be chosen" rule can be SELF-PRINTED (`Card.can_be_chosen_by`, Zidane) or GRANTED to another card
(`Field.is_protected_from_being_chosen`, Dajh -> Sazh, Serah -> Snow). The granted form is a continuous field query
asked from `_card_matches_criteria`, so the blue ring, click validation and the AI's targeting all inherit it.

**It is asked ONLY at the choosing gate.** "All the Backups" effects still hit a shielded card: it was not chosen. Do
not add the check to `_cards_matching` / `apply_effect`.

Data: `"shields": {"targets": {"is_named": "Sazh"}, "from": "opponent", "by": ["Summon","Ability"]}`.

## Break Protection (Auron)

Protection is a CONTINUOUS QUERY, not a status stamped on each protected card:
`Field.is_protected_from_break(card, source_controller, source_kind)`, asked at the top of `break_card()`. The rule
lives on the protector as `"protects": {"targets": {...}, "from": "opponent", "by": ["Summon","Ability"]}`, with
`targets` read from the protector's perspective. Late arrivals are covered for free; nothing needs cleanup.

**The break must know its cause.** `Card.suffer_damage(damage, kind, controller)` records `last_damage_kind` /
`last_damage_controller` (empty kind = combat, which also clears a stale record), and the state-based sweep passes them
into `break_card()`. `damage_targets` / `damage_forward` / `break_targets` pass `_effect_kind()` ("Summon" if the
source card is a Summon, else "Ability") and `_current_controller`. Any NEW damage path must do the same or protection
will silently not apply to it.

## Divide Damage

"Divide N damage among them as you like" is a `divide_damage` instruction, but the PLAYER'S CHOICE happens **before
the ability commits** — in `Stack._on_assistant_target_complete`, not at resolution. That is what makes Cancel on the
distribution able to step back to target selection (re-push the TARGET modal, re-emit `request_target_confirmation`);
a resolution-time modal could not, because the effect is already on the stack with locked targets.

The window is `party_split.tscn` with `allow_cancel = true` (Back button + Escape, emits `finished([])`). The blocker's
party split leaves it false. Amounts are stored on `Game._damage_division` — one slot, consumed by `divide_damage()`
in `_targets` order.

## Blocking Legality

Two predicates, one per side of the pair: `Card.allows_blocker(blocker)` (attacker-side `cannot_be_blocked_by`) and
`Card.can_block_attacker(attacker)` (blocker-side `cannot_block`). `Field.can_block()` is the ONLY gate — the blue
ring, the click handler and `AIAgent.decide_blocker` all read it, so they cannot disagree.

**A party is blocked if the blocker can legally block AT LEAST ONE member** (Advanced Rules 15.1.1.9.6), not if it can
block every member. A party of Yuffie 86 (no cost 3+) + Yuffie 85 (no cost 4+) is blockable by a cost-3 Forward.

## Multiple Abilities on One Card

`card_effects["skill"]` is a list. `Field.begin_skill_activation(card)` with a NEGATIVE index means "ask the owner":
one entry activates directly, 2+ open `skill_choice.tscn` through `Agent.choose_skill(player_id, card, skills,
usable)`. An explicit index still bypasses the picker.

`usable[i]` is false when an ability's cost cannot be paid right now (an S ability needs a card of the same name in
hand). The picker shows those disabled; `can_activate_now()` offers the card if ANY entry is usable. Nothing is tapped
or paid before the choice is confirmed.

Give each skill a `"text"` key for the picker; otherwise it falls back to a cost + instruction summary.

## Card Effect Data Traps

**`apply_effect` placement.** On a TRIGGER (`when_enter_field`, `when_cast`, `when_attack`, ...) it must be TOP-LEVEL,
next to the keyword:
```json
"24": { "apply_effect": {"is_type":"Forward","controller":"opponent"},
        "when_enter_field": { "instructions": [...] } }
```
Nested inside `when_enter_field` it is silently ignored — there is no error, the effect simply targets nothing. Inside a
`skill` definition it belongs in the skill object (skills read it from their own def).

**`play_card(animate = false)` does not fire ETB.** That is the SETUP path for pre-placed boards: those cards were not
"played". A probe that wants an ETB must call `execute_card_effect(card, "when_enter_field")` itself; a real play from
hand uses `animate = true` and fires it on the tween's `finished`.

**Multi-target triggered abilities.** A single target is attached by `request_target_confirmation` on each pick; a LIST
is copied onto the stack object in `Stack._on_assistant_target_complete` when the player confirms early ("up to 5").

## Party Triggers

**Criteria predicates take exactly ONE argument.** `matches_criteria` calls every key with `callv(name, [value])`, so a
predicate declared `func is_character() -> bool` is an invalid call, every candidate becomes illegal, and targeting
silently finds nothing. Declare `func is_character(_want = true) -> bool` even when the value is unused.

**Trigger-level vs instruction-level conditions.** `when_*` blocks may carry `"condition": "..."`, evaluated in
`Field.execute_card_effect()` before the effect is queued. Use it when the condition decides whether the ability
happens at all — a conditional trigger that still selects a target and resolves an empty effect is wrong. Instruction
conditions are for "do A, and only if it worked do B". `party_has_named:<name>` is the party-with-X condition.

**`resolve_top_effect()` is not a completion barrier for async instructions.** It empties the stack, but the
instruction pump keeps running fire-and-forget; an instruction that awaits an animation (return to hand) lands later.
Probes asserting animation-driven results must wait.


There are THREE party triggers, and picking the wrong one silently does nothing:

| keyword | when | fired by |
|---|---|---|
| `when_party_attack` | THIS card is in the party and it attacked (≥2 members) | `Field.execute_card_attack`, per member |
| `when_party_attacks` | a party you control attacked (any card you control may watch) | `Field.trigger_party_attacks` |
| `when_party_deals_damage` | a party you control dealt player damage (unblocked only) | `Game.cause_attacking_damage` |

Use `when_party_attacks` for Backups and bystanders ("when a party you control attacks"); `when_party_attack` only for
text that says "when THIS card forms a party and attacks". Both need a REAL party (≥2 attacking members).

`power_change_party(amount, duration)` reads `Field.party_members()` at RESOLUTION (the party is still selected;
`reset_attacker()` only runs after the damage step). `party_brave: true` on a card grants Brave to its controller's
party members through `Card.is_brave()` → `Field.party_grants_brave()`.

## Test Grounds (one board per mechanic)

Adding one is three edits in `scripts/test_grounds.gd`: a builder function, an entry in
`GROUNDS` (title + blurb) and an arm in `config()`. `test_grounds_probe` then checks the ids, the board it boots and
anything the ground specifically claims. Also add the ground to `CATEGORY_OF`; the Test Mode menu lays categories out
in four columns from that mapping.

`scripts/test_grounds.gd` is a registry of curated boards, reached from the main menu's **Test Mode** button
(`test_grounds_menu.tscn`). The main menu itself is unchanged — the grounds are deliberately NOT presets there.
Use these instead of the general `ai` preset whenever you are testing one mechanic: the `ai` board also casts Ifrit/Valefor, so the board
changes under you.

| ground | for | opponent |
|---|---|---|
| `party` | forming/attacking with a party (ice pair on both sides) | **mock** — never plays or attacks |
| `party_ai` | blocking a party, which opens the damage-distribution window | **ai** — ice pair, EMPTY hand, so it only attacks |
| `summons` | Summons + target protection (Zidane vs Ifrit) | ai, holds Ifrit |
| `break_zone` | fragile/exile (you hold Bahamut + mana) | mock |
| `mill` | milling (Rikku/Thief + wind mana) | mock |
| `terra` | Summon surcharge + Terra's own protection | mock |
| `counter` | countering a Summon — target the Ifrit ON the stack with Summoner | mock (you cast the Ifrit yourself) |
| `clean` | empty board, empty hands, seeded decks | mock |

Conventions when adding one: `opponent_type: "mock"` when YOU drive the mechanic; `"ai"` when the other seat must act;
give the opponent an **empty hand** unless the mechanic needs it to cast; decks start at id 101 so board cards
(1-100) never collide; no shuffle, seed 0 — a ground must be identical every time.

Adding a ground = one entry in `GROUNDS` + one arm in `config()` (a Dictionary of Callables is not a constant
expression in GDScript). `tests/test_grounds_probe.tscn` validates every registered ground, so a typo'd id or a
missing key fails loudly.

## Build / Test / Run

**Preferred: the headless probe** (see *Running Godot* above for the one allowed command). It is the fastest check and needs no editor and no clicking:

```bash
GODOT="/c/Users/KABUM/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
"$GODOT" --headless res://tests/arrow_probe.tscn --quit-after 900
"$GODOT" --headless res://tests/flow_probe.tscn --quit-after 5000
```

It prints a `[ArrowProbe]` report with a `RESULT:` line, so pass/fail needs no interpretation.

**Also available: a headless boot to catch compile errors**, which does need the user (or an allowed run):

```bash
"$GODOT" --headless --path "C:\Users\KABUM\Desktop\TCG Project\TCG-Simulator-on-Godot" --quit-after 40
```

- Use the Godot **4.7.2** binary (nested inside a same-named folder under `~/Downloads`). `Godot_v4.4-stable_win64.exe` on the Desktop is the **wrong** version.
- Success = 0 `SCRIPT ERROR` / `Compile Error` lines. Add `res://game.tscn` as a positional arg to boot straight into a match (uses the `debug` preset) and also expect `Entering: 2` (FIRST_MAIN_PHASE); the menu boot cannot reach it, since it waits for a button press.
- Anything about how it **looks** still has to be seen — the probe verifies geometry, wiring and invariants, not taste.
- `--check-only --script <file>` is unreliable here: autoloads are absent, so it false-errors with `Identifier not found: CardDatabase / GlobalVariables`.

## Architecture Map

| Path | Responsibility |
| --- | --- |
| `scripts/main_menu.gd` + `main_menu.tscn` | Entry point. Builds the menu UI in code; starts a preset match via `MatchSetup.start_match()`. |
| `scripts/match_setup.gd` (`MatchSetup` autoload) | Match config seam: presets (`ai`, `standard`, `debug`), pending `config`, `start_match()` / `go_to_menu()` / `resolve_config()`, and the seeded shuffle (`_pick_seed()` / `_shuffled()`), applied by `_standard()` **only** so the practice presets keep their hand-picked boards. Future home of real decklists. |
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

- **Phases:** ACTIVE → DRAW → FIRST_MAIN → ATTACK_PREP → ATTACK_DECL → BLOCKER_DECL → DAMAGE_RES → (loop to ATTACK_PREP) → SECOND_MAIN → END. Turns **alternate** (`turn_owner = 3 - turn_owner` at end of turn); the turn owner untaps in ACTIVE and draws in DRAW. **Priority:** the turn player receives it first in a phase/step; a player with priority either **acts** (which hands priority to the other player) or **passes**. The game only moves on when both pass consecutively with no action in between — then the top of the stack resolves (after which the **turn player** has priority again) or, with an empty stack, the phase advances.
- **Who acts is decided by the agent seam.** `Game.agent_for(player_id)` → `Agent` (`scripts/agents/`): `LocalAgent` (human: pass button, attacker clicks, **blocker clicks**), `MockAgent` (passes, never attacks/blocks), `AIAgent` (plays an affordable card in a main phase, **Summons included** — it picks their target through `choose_target()`; attacks with its strongest Forward that does not trade down, keeping one home to block; blocks only with a strictly bigger Forward). Chosen from `config["opponent_type"]`. Two method shapes: **pull** (`decide_attacker`, `decide_blocker`, `pay_cost` — return the answer) and **drive** (`choose_target`, `choose_card_in_hand` — perform the inputs a human would have clicked, then let the existing signal continuation run; `LocalAgent` does nothing for those because the human *is* the input). `take_priority()` additionally **returns bool**: `true` = the player performed an action, `false` = they passed.
- **A Character (Forward/Backup) is the slow play:** only the **turn player** may play one, and only while the **stack is empty** (`Hand.charge()` → `Hand.can_play_character()`, and `Card.can_be_played()` asks the Hand for it). Summons and abilities are the instant-speed plays and are legal with a stack. A non-turn player playing a Character needs **Back Attack**, which is not implemented.
- **Damage:** `Card.accumulated_damage` counts **up**. Break iff `accumulated_damage >= power` (equal damage breaks). `power <= 0` → put into Graveyard, which is **not** a break (no `unbreakable` protection, because it never broke). End Phase cleanup resets all damage and expires "until end of turn" effects.
- **Zones:** incoming damage → Damage Zone (cards off the deck); breaks/removals → **Break Zone** (= `Graveyard` node); exile → **Removed** pile (`Card.Zone.REMOVED`). The Break Zone and the Removed pile are the **same scene** with a different exported `zone` — that export is what keeps them separate, so never assume "it is in the graveyard node" means "it is in the Break Zone".
- **Break Zone triggers are fired BY THE PILE, after arrival.** `Graveyard.add_card()` reads `from_field` + `card.broken` **before** moving the card, lays the pile out, clears `broken`, then calls `Game.trigger_break_zone_keywords()`. `when_enter_break_from_field` fires for any card arriving **from the field** (broken or not); `when_break` only when `broken` was true. A discarded/milled card fires neither, and an exiled card fires neither because it never reaches the pile.
- **`fragile` is a REPLACEMENT effect** ("if it is put into the Break Zone this turn, remove it from the game instead"). It lives in `_send_card_to_graveyard()` — the single choke point both field→graveyard paths use — which redirects to the Removed pile and returns `true` so `break_card()` skips the break trigger. Applies to **any** later death that turn, not just the damage that granted it, which is why Bahamut applies it before its own damage.
- **Win condition:** a player loses at `PlayerSide.DEFEAT_DAMAGE` (7) cards in their damage zone, and also if their deck cannot supply the cards for damage. `PlayerSide.take_damage()` emits `damaged(self)`, which `Game._on_player_side_damaged()` listens to — so **any** damage source, present or future, is covered; don't re-check defeat at call sites. `Game._end_match()` sets `match_over`, which `next_phase()` checks to stop the machine before returning to the menu.
- **Effects are data-driven.** Keywords: `when_enter_field`, `when_attack`, `when_cast`, `when_cause_damage_to_player`, `when_enter_break_from_field`, `when_break`, `ex_burst`, `skill`, `aura`, `conditional_power`, `cannot_be_chosen`, `haste`, `brave`, `first_strike`. An instruction is `{name, author, argument}` plus an optional `condition`; executors resolve in `Game._resolve_executor` (`card`, `target`, `game`, `player`, `opponent`, `field`, `hand`, `deck`, `assistant`). `search_deck` takes a **destination** (`hand` default, `top`, `removed`, `graveyard`) and reports success via `_last_action_succeeded`, which `condition: "if_last_succeeded"` reads.
- **`cannot_attack` is a status checked in `Card.can_attack()`, never in `can_tap()`.** "It cannot attack this turn" stops the attack declaration; it does **not** stop the card being dulled to pay a cost. Same family as `block_disabled`, which `Field.can_block()` honours.
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

- **A camera is identified by WHERE IT IS, not what it is called.** A damage camera is any `Camera3D` inside a `DamageZone`; that is what `Game._zoom_to_damage()` and `start_match()` both look for. Names were tried first and failed **three times in one day** — the node was built as `CameraPlayerDamage` while the code looked for `CameraDamagePlayer`, then renamed to plain `Camera`. Position is something a scene cannot get wrong by typing. The old names survive only as a fallback for a camera left at the root.
- **Godot activates the FIRST `Camera3D` in the tree when none is marked `current`.** Move a damage camera above the board camera and the match starts looking through it: the board appears upside down (its look direction is `(0, +0.97, -0.23)` — upward — against the board's `(0, -0.98, +0.17)`), and every probe that measures screen positions fails. `start_match()` now picks the board camera itself — the camera that is NOT inside a damage zone — and makes it current, so **scene order is not load-bearing**. Do not "simplify" that by asking `get_viewport().get_camera_3d()`: at that moment it may already be a damage camera, which also makes the zoom's return trip a no-op.
- **A verification claim must come from the RAW output.** Grepping a probe's output for its own tag hid a `SCRIPT ERROR` underneath, and a truncated list was read as a pass — a commit claimed "verified" on a run that had crashed. Check the **error count** and the **tail** of the output, not a filter of it.
- **An assertion must describe what a person will SEE.** `edge_depth > 0` passed on a 1.6 px bottom line nobody could see; `frac > 0.4` failed the moment the preview was made sensibly smaller. Use **bands and pixels** ("2–6 px", "0.25–0.55 of the viewport"), not "a value was set". This is the same class of mistake as a check that passes for the wrong reason, pointing the other way.
- **A flag does not make a change safe.** The tiles experiment sat behind `use_tiles_on_field`, yet `_apply_visual_mode()` ran on **every zone change for every card**, so turning the flag off still went through the new code and the field stayed broken. It was reverted wholesale. **Probes check game state, and a visual regression passes all of them** — prove a flag-guarded path is inert when off, or don't ship it.
- **Build a new look in isolation first.** The tiles failed because a whole visual swap was wired into the live card in one step. The hover preview worked because it is **additive**: reachable only from a hover, only on a field-zone card, through two accessors that did nothing before. A scene like `tests/card_tile_preview.tscn` or `tools/shot.tscn --camera <name>` lets the look be judged before anything depends on it.
- **Measure the RENDER, not the model, for anything about how something looks.** `tools/hand_outline.tscn` traces the lowest grey-ish card pixel down every column of a screenshot and prints the row profile as text — enough to settle "which way does this curve go" in one run, where camera arithmetic and the screen disagreed four times in a row. Screenshots come from `tools/shot.tscn` (windowed; **never** `--headless`). Reach for this **first** when a complaint is visual.
- **`UnderstandImage` is a remote service** with a 60 s per-image upload timeout (`filesApiTimeoutMs`, max 600 s). "fetch failed" / "did not complete" is that upload path, not a bad file. `deepseek-v4-flash-vision-exp` reads local images directly; otherwise the pixel tools are usually better anyway. Don't retry it more than twice.
- **Everything screen-relative is derived from the camera, never from a local axis.** `Hand._screen_down()`, the screen-right sign in `calculate_card_position()`, and the depth ramp are all derived, because the two `Hand` nodes are not oriented the same way (the player's is flipped 180° about Y, the opponent's is not). Writing any one of them by hand has produced a bug four separate times.
- **`Hand.mirror_presentation`** turns over the whole opponent presentation: the row hangs off the TOP edge by `FAN_VISIBLE_FRACTION`, the arc turns over (ends higher — the happy face), the cards are dealt face down, and the pointer does nothing to them. The LEAN is deliberately **not** mirrored; flipping it too is the mistake that kept coming back.
- **The hand's stacking order is a depth ramp along the camera axis** (`Hand.CARD_STACK_HEIGHT`), so it costs zero screen movement under an orthographic camera — which is why it can be 20 mm without disturbing the fan. It must stay wider than the glow quad's 2 mm offset, or a card behind shines through the one in front.
- **State ownership:** match state (`phase`, `priority_holder`, `turn_owner`, `phase_index`) is owned by `Game` and must not be copied elsewhere. `Field.phase` is a read-through getter to `Game.phase`. `GlobalVariables` holds only local presentation state: hand-layout constants, the UI signals, and the input mode.
- **Input mode is derived, never assigned.** `effective mode = top of modal stack OR base mode`. `Game._enter_phase()` calls `set_base_mode(default_mode_for(phase))`; modal flows call `push_modal(...)` / `pop_modal(...)` (`TARGET`, `PAYING_COST`, `CHOOSE_CARD_IN_HAND`, `ATTACKING`, `BLOCKING`); `refresh_mode()` re-applies the layers without disturbing an open modal. There is deliberately **no `set_player_mode`** — don't reintroduce one.
- **Declaration buttons follow the same rule as the modals.** `ASSISTANT.set_declare_attack_button()` / `set_declare_block_button()` are driven by `Field.attacker_changed` / `Field.blocker_changed` — and **both signals fire for either side**, so their handlers (`Game._on_field_attacker_changed` / `_on_field_blocker_changed`) must bail unless the matching mode (`ATTACKING` / `BLOCKING`) is open. Without that guard the human is offered a button for the opponent's attacker/blocker.
- **A modal is popped by the same layer that pushed it,** exactly once. Target cancel is driven by the `target_cancel` signal into Field *and* Stack, so only `Assistant.on_target_cancel()` / `on_target_complete()` pop `TARGET`.
- **Blocking invariants:** `Card.declare_blocker()` only *records* the blocker — via `Field.blocker_card`, which survives `_clean_instruction_stack()` — and the single clash lives in `DAMAGE_RESOLUTION`. Never clash at declaration time (it would apply twice and be invisible to the damage step).
- **`Field.attacker_changed` fires for both sides** (both attackers use the same Field). Anything reacting to it must check the input mode: `Game._on_field_attacker_changed()` bails unless `player_mode == ATTACKING`, otherwise the human is offered an Attack button for the opponent's attacker.
- **The mana crystal row:** `mana_crystal.tscn` + `scripts/mana_crystal.gd` + `shaders/mana_crystal.gdshader`, placed by `Assistant`'s cost readout and fed by `Assistant.payment_breakdown()`. One crystal per point of cost. `element` is what is being *asked* for (`"fire"` → a ruby, `""`/`"any"` → white) and `paid_element` + `lit` are what *paid* it, so a white wild crystal paid by a red source turns red and glows. Colours come from `CRYSTAL_TINT` (the badge palette with fire overruled to a ruby — the badge accent is an orange).
- **The crystal shader goes on SURFACE 0 ONLY**, via `set_surface_override_material(0, …)`. `neo_crystal3.glb` is built as two surfaces: `Material.001` is the body and `Material.003` *is* the black edge and outline geometry. A full `material_override` deletes the edges.
- **Faking a black outline in Godot is a dead end here.** A fresnel cannot outline a faceted solid — a flat face's normal never goes grazing, so the rim term is constant per face. `grow_amount` tears at sharp tips, because the exporter splits them into one vertex per face. A `fwidth` crease detector needs *flat* normals, which then have to be rebuilt with `deindex()` + `generate_normals()` or the averaging survives. Author edges in the mesh instead.
- **Two unit traps.** `grow_amount` is in MODEL units, so it scales with the node — 0.02 on a 3.81-unit model drawn at 0.26 m is 0.17 px, invisible; the working value is ~0.12. And **emission is added on top of a lit surface**, so past a point it clips a bright colour's channels and destroys its hue (the ice crystal went pure white at 1.7). A stronger glow needs bloom — and `gl_compatibility` **ignores Environment glow entirely**, verified by rendering. The fallback is an additive halo sprite.
- **The game's lighting, for anything shaded:** one `DirectionalLight3D` pointing straight **down** (`sky_mode = 1`, no shadows), plus ambient = 60% procedural sky + 40% white at 0.3 energy. So `dot(NORMAL, LIGHT)` is essentially *upness*, and anything shaded by direction is stable under a spin about Y — which is the only kind of spin a crystal does.
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
- **A "locked" arrow only locks its DESTINATION, never its origin.** `BallisticArrow.lock_arc()` fixes the tip, but the source card can still be moving — an opponent's Summon is tweened into the stack over 0.3 s and the AI locks its target a frame or two after casting. So `_process()` must rebuild the ribbon when the origin moved *even while locked* (`locked_target` is remembered for exactly this). Rebuilding only when `not locked` left the arc anchored between the caster's hand and the stack (`x = -0.73` where the card settled at `-4.52`). When testing an arc, assert on the **mesh vertices**, not on `start_pos`: `start_pos` tracks through a one-frame lag, so it can look right while the drawn ribbon is stale.
- **Legality and visibility are different questions.** `is_valid_target` is state (agents select by it, and it gates local clicks); the ring is communication, and it means "the game is asking **YOU**". `Card.set_valid_target(value, glow)` keeps them separable, which is why an opponent's targeting shows no blue — only their pick, in red (`set_targeted_highlight()`). Blue = "you may pick", orange = "you picked", red = "they picked".
- **`Stack.hand` is the LOCAL player's hand** (`Player/Hand`), so it is the wrong target for anything an opponent owns. Use `Stack._owner_hand(card)` (→ `Game.hand_for()` by the card's controller) when committing or cancelling a Summon. Committing through the wrong hand leaves a stale `charging_card` there, and `Hand.cancel_summon_cast()` then pulls that card back off the stack.
- **The red reveal has a lifetime; keep it.** It is set when the opponent's pick is confirmed, and must be cleared at BOTH ends: `Field.clear_targeted_highlights()` from `Stack.resolve_top_effect()` when the stack empties, and `Card.enter_zone()` on any zone change (or the ring rides into the graveyard). Nothing else clears it for a non-local pick — `Game.finish_target()` is wired only to the local Confirm button — so a card can otherwise keep a red ring for the rest of the match. When checking a cue's life, assert on `_highlight_on` / `_targeted_highlight_on` at several moments (just after the pick, mid-resolution, after cleanup), not once.
- **A parked card is face-down.** `Stack.park_card()` calls `Card.set_revealed(false)` for any card the local player does not own, so a cost being paid is not public knowledge. Every exit must call `Stack.reveal_parked(card)`: `cast_card()`, `_commit_summon_to_stack()`, `_on_assistant_charge_cancelled()` and `_on_assistant_target_cancel()`. `set_revealed()` restores the cached `mat`, never rebuilds it — rebuilding drops the shader's `effect_enabled` highlight.
- **Priority is a pass chain, not a fixed round order.** `Game.priority()`: the turn player starts; an **action hands priority to the other player**; only two consecutive passes (no action in between) resolve the top of the stack — after which the **turn player** has priority again — or advance the phase when the stack is empty. `Agent.take_priority()` must **report** whether the player acted; inferring it from stack growth is what let the AI cast Ifrit and then play Dark Knight with Ifrit unresolved, because a played Character never touches the stack. Do not "simplify" this back to a fixed `[turn_owner, 3 - turn_owner]` loop. A local player's window ends at `Game.priority_window_ended(acted)`, emitted either by the pass button (`_on_priority_passed`) or by the action choke points in `Stack` (`note_action_taken()`).
- **The card face is a flat quad in the XZ plane: 0.429 x 0.6 m, normal +Y** (`card.tres` AABB `(-0.2145, 0, -0.3, 0.429, 1e-05, 0.6)`). The visible mesh is `HandMesh`; `FieldMesh` is authored in `card.tscn` but nothing ever makes it visible. Take card geometry from `Mesh.get_aabb()` (`Card._card_face_size()`), not a constant — anything laid over the card must be a `PlaneMesh` in that same plane, unrotated.
- **Prompt glow:** `shaders/target_border_material.tres` holds the whole look (the shader `shaders/target_border.gdshader` is just its fallback) — tune it in the Inspector, never by editing constants in `Card`. `Card._build_target_border()` duplicates the material per card, supplies `card_size` from the mesh AABB, and **derives the quad's `margin` from the material's `border_width` + `glow_width`, writing it back** — the quad's edge is what crops the glow, so it must never be hand-tuned in parallel with the widths. The look is deliberately CSS-shaped: `border_width`/`border_color` are the ring (a solid band from the card's edge outward — the thickness knob), `glow_width`/`glow_color` are the spill past it (box-shadow blur). The earlier two-exponential-lobe version had no edge at all, which is why no parameter visibly controlled thickness. The quad is a `PlaneMesh` child of `HandMesh`, not of the Card, because the hand's hover animation moves and scales the *mesh*: parenting to the Card leaves the glow behind. `Card.set_highlight(bool)` is the only entry point: `set_valid_target()` drives it for field targeting, and `Hand.refresh_highlights()` glows hand cards **only** during `CHOOSE_CARD_IN_HAND` and only those matching the criteria. It is deliberately **not** a "you could play this" hint — a normal main-phase hand stays dark (that was a misreading of the requirement once; don't restore it). `blend_mix` (alpha — **not** additive: additive always merges with what is behind it, which is exactly what made the ring wash out to white over bright artwork) + `depth_draw_never`, nothing emitted inside the silhouette; the opacity knobs are `border_alpha` (where the ring meets the card) grading to `border_alpha_far` at the ring's outer boundary — so the light thins with distance from the card — plus `glow_alpha` for the spill. `Card.set_selected_highlight(bool)` swaps the ring to the orange `SELECTED_*_COLOR` set on that card's own material copy (the stock colours are cached in `_build_target_border()`): `Field.set_target_card()` drives it for field targeting — clicking another valid target MOVES the selection rather than being ignored — and `Hand.toggle_effect_card_selection()` for a chosen hand card. **Blue = legal, orange = the one you picked.** One cosine wave drives both pulses: brightness (`pulse_amount`) and a deliberately slight width swell (`pulse_width`) that re-evaluates the band.
- **A ring must be LIT as well as coloured.** `Card.set_highlight(bool)` is what raises the ring's intensity; swapping `border_color`/`glow_color` on a dark ring shows nothing on screen. That is why the red reveal shipped invisible, and it is the classic failure mode here — the state and the colour can both be right while the screen shows neither. The ring has FOUR meanings sharing one material (`_prompt_glow` blue, `_selected_highlight_on` orange, `_targeted_highlight_on` red, `_available_highlight_on` green) and `Card._refresh_target_ring()` is the single owner of both colour (priority orange > red > green > blue) and visibility (lit if any is on). **Never write to `_border_material` from a setter** — with four writers the last one decided the colour. `set_highlight()` is the renderer only; use `set_prompt_glow()` for "the game is asking you" (hand and field share the flag). When asserting a cue, check the RENDERED flag (`_highlight_on`), not only the meaning flag; and `_highlight_on` alone means "some ring is on", not "blue".
- **Every reset path must clear EVERY meaning, and adding a meaning means re-auditing them all.** The clearers are `Field.reset_targets()` (session over: blue + orange + red), `Field.clear_targeted_highlights()` (stack empty: red) and `Card.enter_zone()` (all four). The orange leak — a resolved ability's target glowing orange for the rest of the match — happened because the red clear was added to `reset_targets()` while the older orange was left out: the code looked freshly reviewed and correct. When you add meaning N+1, grep for every place that clears meaning N rather than trusting the one you are editing.
- **A cue is worth having only if it is true.** The green availability ring (`Field.can_activate_now()` → `refresh_available_effects()`) is gated by the SAME predicate as the action (`begin_skill_activation()`), so the two cannot drift; when that gate was four `if ... return` lines living only inside the action, the cue was a copy waiting to go stale. That gate needs **two** things the first cut conflated: the input mode must allow acting (`FREE`/`INSTANT_SPEED_TIME` — a modal taking the moment away darkens the ring), **and the window must actually be yours** (`Field.has_priority()` → `Game.priority_holder == 1`, and false once `match_over`). The mode cannot answer the second question: while the OPPONENT holds priority the mode is still `FREE`/`INSTANT_SPEED_TIME`, which is why gating on it alone lit the ring during the opponent's window. Don't let a cue be driven by a proxy for a question the proxy does not answer. Availability is derived from many causes, so it is POLLED every 0.15 s rather than hooked to one trigger — a single trigger always misses a case.
- **One screen, one owner per signal.** Adding the stack's hover review link gave the aura TWO writers — the link and the targeting reveal — and the link's "clear only what I lit" bookkeeping is indistinguishable from the reveal's when both light the SAME card, so the link stole the red ring and then cleared it, breaking three probe checks. The link now draws the ARROW ONLY and releases it at the START of any session (`Field.request_target()` → `Stack.release_target_display()`), so ownership never depends on refresh order. Before giving a signal a second writer, ask what happens when both write the same object; the honest alternative is to make the signal DERIVED in one place.
- **A newly added `class_name` does not exist for a headless run.** Godot's global class cache is regenerated by the editor only, so `card.gd` referencing `StackCardState` failed to parse with `Identifier "StackCardState" not declared` — and that one parse error cascaded into 9 failures across the other probes. Reference new classes by path (`const STACK_CARD_STATE := preload("res://scripts/stack_card_state.gd")`), or open the project once in the editor to register them.
- **Every arrow belongs on the `Field`, because `BallisticArrow` works in LOCAL coordinates.** `set_is_aiming()` stores its origin and `lock_arc()` its destination, and the mesh is built from them *directly* — so they are interpreted in the arrow's own parent frame. The `Field` (and the game root) have identity-ish transforms, so global points are correct there; the **Stack is flipped and lifted**, so an arrow parented to it and given global points lands wherever that transform carries it. That is what "arrows in random places" was: the review link was instantiated as a child of the Stack. The same rule is why `Card.get_global_top_centre()`/`get_global_face_centre()` can be passed straight through for the live arrow, the block arc and the review link.
- **Metal is a reflection, so an empty environment makes it impossible.** `game.tscn` had a `PanoramaSkyMaterial` with no panorama assigned and `ambient_light_sky_contribution = 0.0`: the sky was black, so every `metallic` surface reflected nothing and read as dull plastic no matter what the material said. A studio sky (bright overhead, dark ground) *is* the gloss — the bright top rim and dark lower band in any chrome reference are that gradient, not a specular highlight. And under `gl_compatibility` there is no SSR/SSAO/SDFGI fallback: **reflections must come from a `Sky` or a `ReflectionProbe`**, so those `ssr_fade_*` values in the Environment do nothing. `tests/button_probe.tscn` asserts all of this. Related: glTF **cannot export Blender's Specular/Coat/Sheen** — they are dropped silently, so set Metallic/Roughness directly or the export will look nothing like the viewport.
- **Targeting arrow: every direction is baked on the CPU, and the shape is asserted.** `ballistic_arrow.gd` samples a `Curve3D` — **one** segment, i.e. two `Curve3D` points — and bakes per-vertex `UV.x` (arc position), `UV.y` (edge) and `COLOR.rgb` (the `side` vector, remapped to 0..1) / `COLOR.a` (arc position again); `shaders/target_arc.gdshader` only *scales* along that baked side and paints additively. Never re-derive a tangent, side or width in the shader from `dFdx`/`dFdy` or from neighbouring UVs: geometry-dependent directions recomputed per-fragment are what pinch and twist a ribbon through a bend. Three facts that cost a lot to learn: **(1) the camera looks almost straight down (~10° off vertical)**, so an arc rising in world Y is foreshortened into a *straight line* — the bow must happen in the screen plane. **(2) A two-segment curve with a handled midpoint has two extrema** (the S-wiggle); one segment whose two controls both sit on the screen-up axis has exactly one apex, and equal controls keep the control polygon convex, so no inflection. `_check_shape()` asserts both on every rebuild and prints the measured peak; `peak_ratio` is derived into the handle as `h = peak_ratio / 0.75`, and `_peak_ratio_for()` trims it so the apex stays `screen_margin` px below the top of the window (floored at `MIN_PEAK_RATIO`). **(3) Vertex `COLOR` is 8-bit UNSIGNED** — bake `side * 0.5 + 0.5` and decode in the shader, or negative components clamp to 0 and the ribbon deforms. Because the shader expands the mesh, `extra_cull_margin` is mandatory or the arrow gets culled; and since `side = tangent × UP` is always horizontal the ribbon sits level with the card faces, hence `render_priority = 100` and the `arc_height` lift. The arrowhead is real geometry anchored to the shaft's **last sample** (a back-off from the tip lands off a curved approach).
- **An arrow's origin must be followed, not captured.** `BallisticArrow.set_is_aiming_from_card()` re-reads `Card.get_global_top_centre()` every frame. A new stack card is positioned by a **0.3 s Tween** (`Stack.update_card_positions()` → `animate_card()`) and starts life at **world (0,0,0)** — which a top-down camera projects to the middle of the screen — so a captured origin is wrong and stays wrong. When targeting a stack effect the source is the **effect copy in the stack** (`Stack.create_card()`), found via `effect_source`, not the card on the field. `Card.get_global_center()` is **not** the centre (it adds a fixed `(0.2, 0.3, 0)`); use `get_global_face_centre()`.
- **The hand is a fan, and its height stagger is load-bearing.** `Hand.calculate_card_position()` spreads cards along an arc (`FAN_RADIUS`) with a per-card tilt (`fan_angle_for()`), and separates them by `CARD_STACK_HEIGHT` (8 mm). That gap must stay **bigger than the 2 mm the glow quad sits above its own card face**, or a card's prompt glow will show through the card lying on top of it (the old layout used 1 mm, which is exactly the bug that looked like a broken depth test). Draw order is the index: higher index = higher = in front. **The tilt sign is inverted on purpose:** `fan_angle_for()` returns the negation of the arc angle used for the positions, because a card's up axis is its local −Z. Flipping only one of the two makes the fan look closed (cards leaning inward) instead of open.
- **Zone presentation has exactly one owner: `Card.enter_zone()`.** `Card.Zone` + `Card.ZONE_PRESENTATION` hold the per-zone scale, rotation baseline and whether the field readout is shown. Every zone transition must call it right after the reparent — `Field.play_card()`, `Graveyard.add_card()`, `DamageZone.add_card()`, `Stack.park_card()`, `Hand.add_card_to_tree()`. Positions stay the zone's own business (and a zone may add rotation on top of the baseline: the hand fan does). Skipping it is what produced the original bugs: `Field.play_card()` preserved the whole `global_transform` so a card played from hand kept the hand's fan tilt, and `Graveyard.add_card()` only set a position, so a broken Forward arrived tilted, oversized and still wearing its power/damage readout.
- **A card's local rotation baseline is NOT always zero — it depends on the container's own basis.** Cards read correctly when turned a half turn about Y from the identity frame (`Card.READABLE_ROTATION`). The `Hand`, `Stack`, `Graveyard`, `Deck` and `FocusCard` nodes all supply that flip themselves (scene transforms are -1 on X and Z), so cards there keep local rotation zero. **`Field` is an identity node**, so field cards must carry the half turn in their own rotation. That is why the "obvious" `rotation = Vector3.ZERO` on entering the field lands every card upside down: the old code inherited the hand's global transform, which silently included the turn. Check a container's basis in `game.tscn` before choosing a baseline for a new zone.
- **The mana crystal row:** `mana_crystal.tscn` + `scripts/mana_crystal.gd` + `scripts/crystal_cost.gd` + `shaders/mana_crystal.gdshader`. One crystal per point of cost; `element` is what is *asked* for (`"fire"` → a ruby, `""`/`"any"` → white) and `lit` means paid, driving BOTH the emissive face glow and the spin speed (18 °/s idle → 150 °/s paid, 0.10 s ramp). **The angle is only ever ADVANCED, never assigned** — that is what makes the two states impossible to snap between. The paid cue is the crystal's own shader; the row's `cost` rebuilds but `paid` must only call `_apply_paid()`, because `_rebuild()` destroys and reinstantiates every crystal and each new one starts at angle 0 (reported as a rotation bug, and nothing of the sort).
- **Payment maths lives in exactly ONE place.** `Assistant.payment_breakdown()` builds one entry per point of the cost; `remaining_cost()`, `can_pay_cost()` and the Confirm button's enabled state are all **derived** from it, so a bug there shows up as a rules bug *and* a UI bug at once. An elemental point can only be paid by its own element — the surplus pass must skip elemental slots, or spare mana of any colour fills them.
- **A skill's tap is part of its cost, so it belongs at ACTIVATION.** `Field.begin_skill_activation()` taps the source before opening the payment modal; if the tap is deferred to `Stack.commit_skill_activation_costs_if_pending()` (via `_apply_skill_source_tap_from_proxy()`) the source is still untapped for the whole mana step and can pay for its own ability. `Stack._clear_skill_proxy()` refunds the tap, but only while `skill_mana_deferred_until_target_confirm` is still true — i.e. only when the player cancelled.
- **`pop_modal()` is NOT a setter — it emits the mode change SYNCHRONOUSLY.** `pop_modal` → `_refresh_mode()` → `player_mode_change.emit()` → `_on_player_mode_change()`, all inside that one call. Anything that must precede the resulting UI change has to be set BEFORE the pop. An `Assistant.cost_row_hold` assigned on the line *after* it arrived too late and the cost row hid anyway, which is exactly what "the crystals disappear as soon as I confirm the payment" was. Same family as the two transform bugs below: **the order of two adjacent lines.**
- **A detached node has no meaningful global transform.** Never read `global_transform` from, or `reparent(..., true)` onto, a node that is not in the tree: the value is just its own local transform, and "keep the global" then does arithmetic against a frame that does not exist — it divided a node's 0.052 scale back out and made every shard ~19x too large. And **`_ready()` runs inside `add_child()`**, so a child cannot see anything its caller sets afterwards (a transform, a colour); give such a node an explicit `burst()`/`setup()` and call it after adding. The engine's `owner ... inconsistent` warnings were pointing straight at this.
- **The crystal shatter triggers on the legal PLAY, not on the payment.** `cast_card()` (a Character to the field, or a Summon cast), `_commit_summon_to_stack()` (a Summon entering the stack), `commit_skill_activation_costs_if_pending()` (an ability with costs paid and target chosen) — all through `Stack._shatter_paid_cost()` → `Assistant.commit_cost_readout()`. `on_charge_complete()` runs BEFORE a Summon's target and before an ability's commit, and both of those can still be cancelled and refunded, so breaking there shattered crystals for plays that never happened.
- **A cost readout outlives its payment.** `Assistant.cost_row_hold` spans the gap between confirming a payment and the play landing; `_hide_cost_readout()` respects it so *every* hide path does (guard it at the choke point, not at the call sites). `commit_cost_readout()` awaits `CrystalCost.shatter_paid()` before hiding, because the crystals break one at a time and hiding on commit would take the later ones away before they broke.

- **`gl_compatibility` cannot do particle trails, bloom, or 2D MSAA.** All three fail *silently or as a warning* and leave the feature simply not rendering: `GPUParticles3D.trail_enabled` **and** a `RibbonTrailMesh` draw pass both print "The Compatibility renderer does not support particle trails."; Environment `glow_*` is ignored; `msaa_2d` warns. Check the renderer BEFORE designing an effect around one of these — the comet trail was built twice because of it. The workarounds are additive halo/annulus quads and a hand-built ribbon.
- **A shader compiles the first time it is RENDERED, so anything appearing mid-animation must be warmed up.** Under Compatibility that compile blocks the frame it happens on, which is why the first absorbed orb stuttered and every later one was smooth. `Game._warm_up_effect_shaders()` compiles a list at match start using 1-pixel quads for one frame. **Add new effect shaders to `EFFECT_SHADERS`.**
- **`depth_test_disabled` means "draw over everything".** The orb's halo had it, added so the orb would not clip its own glow, and it made the halo ignore the depth buffer entirely — so a payment orb stayed visible *through* the card it was meant to vanish behind. Ask whether the flag is doing anything before keeping it; here it was not, because the core is transparent and writes no depth either, so it cannot clip the halo.
- **The card's ring has FIVE meanings, in priority order orange > red > green > blue > energized,** all owned by `Card._refresh_target_ring()`. Energized is checked FIRST because later wins, and it is deliberately the quietest: thinner (`ENERGIZED_WIDTH_SCALE` 0.35), dimmer (`ENERGIZED_DIM` 0.65), and coloured by the card's element (`Card.ELEMENT_COLOURS`, keyed by the CJK character `element` holds) rather than by the mana. Set from `absorb_power()`, cleared when the stack takes a new top card or the card changes zone.
- **A payment volley must not ratchet the card's scale.** `Card.absorb_power()` records its resting scale only on the FIRST hit of a volley (`if _absorb_tween == null or not _absorb_tween.is_valid()`), because orbs land ~0.1 s apart and a later hit would otherwise record an earlier punch's inflated size as "resting" and settle there — a permanent size increase per volley.
- **The payment arc's Y cap is the orb's ORIGIN, not the lower endpoint.** The crystal row sits above the board, so `minf(from.y, to.y)` is the *card's* level: capping there drops the orb to the card's height on the first frame and flattens the whole flight into a horizontal glide. The bow is flattened in Y as well, so the arc may only descend.

- **Anything read after an `await` must be captured in a local BEFORE it.** An await does not merely allow other code to run, it requires it: `cast_card()` suspended for the payment orbs, the caller cleared `casting_card` while it was suspended, and on resume `field.play_card(casting_card, …)` dereferenced null and crashed the game. Capture the node/flag/value into a local first, and use that. This is the strongest form of the project's most recurring class: transform set before `add_child`, `cost_row_hold` set after `pop_modal()`, resting scale read mid-punch, glow set after `enter_zone` cleared the rings, member read across an await — every one is "two pieces of code that assume nothing happens in between".
- **`Stack._shatter_paid_cost()` suspends for ~0.8 s.** It awaits `Assistant.commit_cost_readout()` → `CrystalCost.shatter_paid()` → the last `PaymentOrb.arrived`, and `cast_card()` awaits *it*. Anything downstream runs with the board mid-animation and `casting_card` already cleared. The Summon and ability paths call it WITHOUT awaiting, which is fine because neither moves a card afterwards.
- **`Assistant.commit_cost_readout()` returns unless `cost_row_hold` is set** — that is the "a mana payment is waiting to be applied" flag, and it is what stops an enter-the-field ability (which lands for free) from shattering the previous payment's crystals and sending orbs at a card nobody paid for. Set in `on_charge_complete()`, cleared on commit, cancel, or target-abandon.
- **`Card.set_energized_highlight()` refuses unless the card is in HAND.** The glow is set when the mana lands, which for a Character is after `play_card()` has already run `enter_zone()` and cleared the rings — so without this it lit a card that nothing would ever clear again, permanently. The rule is what the glow is for: a card you have paid for but not yet played.

- **The hand's hover is split across two owners, on purpose.** The hovered card's own LIFT is on its mesh (`mesh_instance_3d.gd`) because that is presentation; where the OTHER cards sit is layout, so the spread lives in `Hand.calculate_card_position()` and is triggered by `Hand.set_hovered()`. Do not move the lift onto the Card (its transform IS the fan layout), and do not put the spread on the mesh (it cannot move its siblings).
- **Never adjust a hover pose in place — build it.** `mesh_instance_3d.gd` used to do `position.y += 0.1` and assign the other three properties outright: the `+=` ACCUMULATED, so a re-enter without a `mouse_exited` walked the card up the screen, and the outright assignments made it snap instead of rise. Compute the pose from the card's current frame and tween to it.
- **The hand hover has three dials and they stack.** `hover_lift`, `hover_scale` and `hover_reach` all push the card "up" on screen, because the board camera is angled steeply enough that coming toward the viewer reads as rising. If it feels like too much, reach for `hover_reach` first — it is the strongest. Note it is a fixed distance toward the camera (the lifted mesh cancels the card's own fan offset first), not a delta, so a smaller number is genuinely less movement.
- **`Hand.update_card_positions()` tweens every card into its slot**, so anything that changes the layout — a draw, a reorder, a hover — animates for free through that one path. Prefer calling it over animating a card by hand.

- **A shader that fails to compile is dropped SILENTLY, and no GDScript will tell you.** Writing `float darken = edge_colour.rgb;` (a `vec3` into a `float`) left every probe check green while the material itself vanished — the cards simply lost their rounding, with nothing the probe could see. Check it with the COUNT of `SHADER ERROR|SCRIPT ERROR|Parse Error` on a boot **and** a grep for the literal word `shader`; a narrow pattern of your own is what hides the message. Godot prints a shader error twice — once as a blank `--Main Shader--` frame and once naming the identifier — so widen the window before concluding the engine is being unhelpful.
- **`get_shader_parameter()` returns `null` for a miss, and `float(null)` is a hard error.** Guard every read-back with `is float` and a fallback. This is the same trap that once collapsed the targeting halo's quad to the card's exact size.
- **Round a texture's corners in a `canvas_item` shader; a raw image has no `StyleBoxFlat`.** One shader therefore owns the rounding, the bottom line and the hover aura together, and every size in it is in UV so the same numbers work at 190 px and 363 px.
- **A line that follows a rounded outline must be measured from the OUTLINE.** Measuring from `UV.y` gives a straight stripe the corner mask merely chops off; `inward = -dist` on the rounded rect's distance field gives constant width that turns with the corner. Its extent along the bottom is a `smoothstep` window (`0.82..0.96`) derived from the corner radius (0.07 UV), not chosen by feel.
- **Never add a bright colour to card art — MIX it.** `COLOR.rgb += aura` clips the channel and washes the border white; `mix()` has been the answer all five times this project has hit additive clipping.
- **Every card image in the editor needs `_round_material()` AND a hover.** The pool thumbnails, the deck rows and the strip piles all go through `_hover_card(node, id, on, aura := null)`. The optional `aura` exists because a strip pile's hover is caught by an invisible button covering the whole pile, while the thing that should glow is the front card image beneath it; the RECT still comes from the cell, which carries the stack offset. Only the FRONT copy takes the material — the ones behind it are dimmed plates.
- **The hover preview is parented to the editor root and positioned from GLOBAL coordinates**, which is what lets it serve controls nested in scroll containers. It must be `MOUSE_FILTER_IGNORE` (one that accepted input would steal the hover that opened it and flicker), it flips LEFT when there is no room to the right, and it CENTRES first and only then shifts up when there is no room below.
- **The two deck views are independent toggles, not a switch.** The list and the card strip can both be up; the layout gives each what it asks for rather than trading one for the other.
- **Read the reference image; do not guess the look.** `references/black.png` was described in one line and a soft 3% gradient was still built instead of the solid thin line it shows. `tools/ref_probe.gd <path>` prints an ASCII map of any PNG, which is how both the icon sheet and that line were actually read.
- **A picker screen exists because a scene cannot be handed an argument.** The choice is left on `MatchSetup.editing_deck_name` and read in the editor's `_ready()`. An EMPTY name means "new deck", so one value carries both the deck and the create/edit distinction. `MatchSetup.list_decks()` is the single reader for what is on disk — the picker and the editor both go through it, so they cannot disagree about what a file contains.
- **Renaming a saved deck must MOVE the file.** `save_deck()` writes to `deck_path(deck_name)`, and `deck_name` is exactly what a rename changes — so without a record of which file the deck came from, a rename writes a SECOND file and leaves the first one behind, which is indistinguishable from the editor having created a new deck. `_loaded_from` is set when the picker opens a deck, when `load_deck()` reads one (taken from the PATH, not from inside the file, which may have been hand-edited), and after every save. A name that is already taken is REFUSED rather than overwritten: silently destroying a different deck to fix a typo is a worse bug than the one being fixed.
- **`MatchSetup.delete_deck()` does not confirm; the caller does.** Confirmation belongs where the user is, not in the file-handling layer, and a future scripted caller should not be ambushed by a dialog. It returns false and prints why when there is nothing to delete, so no caller can report a successful delete of a file that was already gone.

- **`custom_minimum_size` is a FLOOR, not a hint.** Setting it to a preferred size silently clamps away any smaller size the layout assigns, so a card pinned at `CARD` stayed 308 px tall while the maths placing it assumed 283 — and the row overflowed its box. A `Control` whose size is computed should have NO `custom_minimum_size`; assign `size` directly.
- **Two functions that decide the same size must agree.** `_card_size_for_height()` (layout) and `_card_size()` (placement) both answer "how big is a card", and they reserved different heights the moment one accounted for the hover growth and the other did not — the same shape as the overflow above. When a value is derived in two places, both need the same inputs.
- **`Control.scale` grows about `pivot_offset`.** The deck search fan pivots at the BOTTOM-centre, so a hovered card's base stays on the arc while the rest swells outward and up, which is what reads as coming toward the viewer. It also means the height budget must reserve that growth ABOVE the row, or the enlarged card leaves the box.
- **Raise a child with `z_index`, never `move_to_front()`.** Reordering a container's children renumbers their indexes, and `_hovered_index` is expressed in exactly those indexes.
- **The image tool is not dependable here — measure instead.** It hangs on the project's full-size reference PNGs and has returned a confidently wrong description of a file it did read. `tools/row_measure.gd <path>` prints a reference's panel seams and content columns, `tools/ref_shrink.gd <path> <width>` writes a small copy the tool can usually take, and `tools/search_shot.gd` screenshots the built window so the implementation itself can be looked at.
- **A screen booting proves nothing about `game.gd`.** The menu never loads it, so a parse error there reports 0 errors on a menu boot and only surfaces when a probe boots `res://game.tscn`.
- **`Tween.parallel()` binds to the tweener added just BEFORE it.** Inserting a second stage between a stage and its parallel turn silently moved the turn onto the wrong step, and the card rotated for the whole flight instead of three quarters of it. Add a `parallel()` tweener immediately after the one it should accompany.
- **Never take a measurement from a downscaled reference.** `references/draw6.png` shrunk to 460 px made the gap between two hand-drawn arcs read as "25–40 px" when at full size it is ~190 px, and three rounds of tuning went the wrong way before anyone noticed. Read the full-size file first; shrink only if the image tool refuses it, and never read a number off the copy.
- **The draw's whole shape lives in one block in `scripts/hand.gd`.** One cubic from the deck to the hand whose control point sits above and to the RIGHT of the destination (that offset IS the shape), 1.7 s of `QUAD EASE_OUT`, a 0.9 s flip finishing at ~76% of the path, and the fan tilt applied only after landing. `tests/draw_probe.gd` samples the flight and asserts all of it — read it before touching any of those numbers.

- **A hover or drag that resizes a card must change the CARD's scale, not its mesh's.** The card's scale is what the zone system and the drag already use, and it is what has to be right when the card lands on the stack — `Hand.set_hovered()` grows a hovered card to `Card.STACK_CARD_SCALE` for exactly that reason. Growing the mesh leaves the card at hand size and loses the effect.
- **Layout does not own size.** `Hand.animate_card()` tweened the card's scale to 1.0 on every re-layout, which made 1.0 the hand's real resting size regardless of `Card.ZONE_PRESENTATION` and quietly defeated a hand that was meant to be 10% larger. If a number lives in the zone table, nothing else may write it. `tests/hand_hover_probe.tscn` READS the card back instead of fixing it up, which is how this was found — a probe that repairs the thing it is testing tests nothing.
- **A CARD'S `scale` IS LOCAL TO ITS CONTAINER, and the container nodes all carry scales of their own.** `Stack` is **2.305**, `Deck` 1.4, `Graveyard` 1.2, `FocusCard` 4.5, `Field` 1.005, `Hand` and `DamageZone` 1.0. So a size written into `Card.ZONE_PRESENTATION` was multiplied by the container before it reached the screen: `Card.STACK_CARD_SCALE = 1.4` drew a stack card 2.3× bigger than the number said, which is why a hovered hand card could never be made to match one. **The numbers in the zone table are WORLD sizes**; `Zone.STACK` divides `STACK_CONTAINER_SCALE` back out to keep that true, and `stack.gd`'s layout tween does the same. Compare **`global_transform.basis.get_scale()`**, never `card.scale`, when the question is how big something looks — and prefer putting a card on the stack and measuring it over reasoning about the table, which is what found this after several rounds of guessing.
- **A spacing change is not just a spacing change — check what else is proportional to it.** The hand fan's arc is `R(1 − cos θ)` with `θ ∝ step`, so the bow grows with the **square** of the step: widening neighbours from 0.38 to 0.86 multiplied the row's curve by five and put the outer cards 16 px above the middle ones, which reads as "some cards are in higher positions". The arc and the lean are now separate numbers (`FAN_ARC_RADIUS`, `FAN_TILT_PER_CARD_DEGREES`) precisely so one cannot drag the other, and `hand_hover_probe` fails if the card centres span more than 12 px vertically.
- **The step between hand cards is an INTERACTION number, not a look.** The hovered card is drawn on top at 1.5× a resting one, so it hangs a quarter of a card over each side: below a step of ~0.6 the pointer can never reach the next card at all. It is exported as `Hand.step_fraction` (0.86, range 0.3–1.4) so it can be dialled in live — **run the game (F5), switch the Scene dock from Local to Remote, select `Player/Hand`, and drag it**; the setter re-lays the hand out immediately. The reference could not supply this number: `UnderstandImage` fails on `references/hand.png`, and `tools/hand_measure.gd` finds only noise where its card borders should be.
- **A WORLD direction added to a LOCAL position comes out reversed, because `Hand` is rotated 180° about Y.** Two bugs at once, and both looked like "the feature just isn't there": the hand's sink-below-the-screen offset moved the row **up** instead of down — dragging cards that were already below the bottom edge back into full view — and the row's arch came out as a **bowl** (ends high, middle low) instead of an arch. Both are ~10 px and easy to stare straight past. Every camera-derived offset must go through the node's own basis first: `(global_transform.basis.inverse() * world_dir) * amount`. `Hand._hover_offset()` already did this; `calculate_card_position()` did not. In this frame, **up the screen is the Hand's local −Z**, so the sag is `+fan_sag_for(i)`.
- **The hand's layout is now a spec, and `hand_hover_probe` is that spec.** Five claims, in the order the probe checks them: the hand stays **centred and on screen** at every size (swept at 1/3/7/10/15 cards — centred at 960.0 of 1920 every time); at rest most of each card is **below the bottom edge**, leaving ~46% (the name-and-cost strip) showing, with the **middle highest** and the ends ~11 px lower; a hover shows the card **whole, upright, enlarged (2.4 = the stack's size), in front of every neighbour**, with at least 40 px of each neighbour left reachable for the pointer; adding and removing cards **re-fans by animating** and settles exactly where `calculate_card_position()` says; and the lean is **2° per card, never more than 12°**. `spacing()` is `min(the dialled maximum, what fits the screen)`, so the hand compresses as it grows rather than running off the sides.

- **`condition: "if_last_succeeded"` is a ONE-BIT LATCH, not an expression system.** "Search … and if you do so …" needed a branch, and the effect language had none. The pieces are deliberately tiny: `Instruction.condition` (parsed from the card data's `"condition"` key, empty = unconditional), one `Game._last_action_succeeded` flag, and a check at the top of `_process_next_instruction()` that pops the guarded instruction and tail-skips to the next one. **Only `search_deck` writes the flag today** (`false` on entry, `true` at the end; a cancel, a missing card or an empty deck all leave it `false`). Two edges worth knowing before extending it: the flag is per-**chain**, so `_execute_instructions()` resets it only when the queue was genuinely empty (`fresh_chain`) — a mid-chain prepend from a triggered ability must not wipe it; and it carries **no result**, only yes/no. When a card needs "put the card you found into your hand", the upgrade is for the instruction's **return value** to be the signal (`if result is bool: _last_action_succeeded = result`) so each verb reports for free, and for an instruction to carry a `"then"` sub-list which `_execute_instructions()` prepends only on success — that gives nesting with no new state machine.

- **The Break Zone is the thing that knows a card arrived, so it is the thing that fires the triggers.** Anything that moves a card field→pile must call `_send_card_to_graveyard()` (the choke point) and let the pile do the rest; firing from `break_card()` or from the instruction layer re-introduces the bug this replaced — effects resolving while the card is still on the field, and power-0 removals silently firing nothing. `Card.broken` is a **one-shot reason flag**: whoever moves the card sets it, the pile clears it after use, so a later event cannot inherit a stale `true`. `trigger_break_zone_keywords()` pushes the effect copies through `field.add_card_effect_to_stack` — the same route ETB/attack triggers use — because `field.execute_card_effect()` requires the card to still be on the field.

- **On an orthographic board camera, the ONLY thing that changes apparent size is scale.** The graveyard and removed piles looked smaller than deck cards and the natural guess was distance; it was not. The board camera is `projection = 1`, so moving a pile nearer changes its size by exactly zero — the pile nodes were scaled 1.2 while the Deck was 1.4. Same rule that makes "come toward the camera" useless as a hover cue: compare `global_transform.basis.get_scale()`, and if a pile looks small, change the container's scale.

- **A pile that shares a scene needs its zone as data.** `Graveyard` and `Removed` are the same `.tscn` with a different exported `zone`; `add_card()` used to hardcode `Card.Zone.GRAVEYARD`, which made an exiled card indistinguishable from a broken one. Any new pile (exile, warp, deck-out) should reuse the scene and set `zone`, and `Card.Zone` values must be **appended**, never inserted — they are written into scenes and printed by probes.

- **An animating action should RETURN its tween, and multi-target animations join with `AnimationBatch`.** `await` inside a target loop serialises: five returned Forwards took ~3000 ms one after another. The Godot equivalent of `Promise.all()` is `scripts/animation_batch.gd` — start every tween, `close()`, `await batch.wait()`; it never hangs on a null/invalid tween and never aborts. That only works if the animation is ONE awaitable, which is why `Hand.begin_return_card()` is a single chained tween (the landing callback is a step inside the chain, not a second tween). Logical changes stay synchronous before the join, so a follow-up instruction sees the right board while the visuals catch up.

- **A stack card leaving the stack is a layout event.** `resolve_top_effect()` must call `update_card_positions()` after popping, exactly as the hand reflows when a card leaves it; otherwise every resolved effect leaves a hole in the fan. `_clear_skill_proxy()` already did this, which is the convention to follow. It also refreshes the hover/review arrow for free, because `update_card_positions()` ends with `refresh_target_display()`.

## Changelog

Maintain `CHANGELOG.md` with `## [Unreleased] — YYYY-MM-DD` sections using Added / Fixed / Changed / Known Issues. Add to the current date's section (don't create duplicate date headings); include file/method names and note unfinished work under Known Issues.
