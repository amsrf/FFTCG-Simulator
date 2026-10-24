import io

p = 'CHANGELOG.md'
s = open(p, encoding='utf-8').read()
head = "## [Unreleased] — 2026-09-11\n"
entry = head + """
### Staged targeting: Hades 52

`choose_target` may now be an **Array of stages**, asked in order:

```json
"choose_target": [ {"is_type": "Forward", "controller": "opponent"},
                   {"is_type": "Backup",  "controller": "opponent"} ]
```

The session advances as soon as a stage is full (the Forward keeps its ring and the blue prompt moves to the Backups),
and Confirm appears once, after the last stage. Right-click steps back across a stage boundary and asks for the
previous stage again.

**Mandatory stages.** `has_viable_target()` returns false unless EVERY stage has a legal candidate, so with no Backup
on the opponent's board Hades cannot be cast at all — the rule the user quoted.

**Instructions can name a stage**: `dull_targets(0)` and `return_targets_to_hand(1)`, via `_selected_targets(index)`.
Every existing `[...]`/no-argument instruction keeps its old "all targets" meaning.

**Resolution now really waits for its instructions.** `_execute_instructions` used to fire the chain and return, so
`resolve_top_effect()` marked itself complete while an instruction was still animating or waiting on a modal. A chain
is now reported finished only from the empty-queue branch (`_instructions_running` + `instructions_finished`), and the
stack handler awaits it. This is what made Hades' "return the Backup to hand, then discard" testable in one pass —
and it was latent for every return-to-hand, discard and modal instruction before.

New probe `hades_probe` (21 checks). Coverage: **85 implemented / 7 plain / 8 to do**.

Known cosmetic issue: one Godot engine `ERROR: Condition "det == 0" is true` appears during the return animation in
this flow. Behaviour is correct; it is an arrow/transform edge case on a card leaving the field mid-animation and is
queued as a follow-up.

"""
if "### Staged targeting: Hades 52" not in s:
    s = s.replace(head, entry, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('CHANGELOG updated')
else:
    print('CHANGELOG already has it')

p = 'AGENTS.md'
s = open(p, encoding='utf-8').read()
anchor = "## Targeting has a DOMAIN: field or stack\n"
note = """## Targeting can have STAGES

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

"""
if "## Targeting can have STAGES" not in s:
    s = s.replace(anchor, note + anchor, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('AGENTS updated')
else:
    print('AGENTS already has it')

for f in ('AGENTS.md', 'CHANGELOG.md'):
    d = open(f, 'rb').read().replace(b'\r\n', b'\n')
    open(f, 'wb').write(d)
