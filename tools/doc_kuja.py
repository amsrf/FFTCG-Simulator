p = 'CHANGELOG.md'
s = open(p, encoding='utf-8').read()
head = "## [Unreleased] — 2026-09-11\n"
entry = head + """
### "When chosen": Kuja 37

A new trigger, `when_chosen`, fired from `Field.notify_targets_chosen()` when a targeting session is CONFIRMED — not
when the rings are clicked:

* **Once per session.** A pick can be replaced before confirming, and a ring-click is not a choice; `_chosen_notified`
  is reset by `request_target`.
* **Only the opponent's choice.** The chooser is `source_card.controller`; if it equals the card's controller the
  trigger is skipped, because Kuja's text says "of your opponent".
* **Only Summon/Ability.** A set effect (`apply_effect`, "all the Backups") never chooses anything, so it does not
  trigger this — the same distinction already used for `cannot_be_chosen`.

`Game._on_targets_confirmed` is connected AFTER the Stack's target handler, so the triggered ability lands on top of
the Summon/ability that caused it and resolves first, which is the correct LIFO order.

Data: `"when_chosen": { "instructions": [ opponent_discards 1 ] }` — `opponent_discards` is controller-relative, so
the discard goes to Kuja's controller's opponent.

New probe `kuja_probe` (8 checks): a Summon choosing it, nothing discarded until resolution, its own controller
choosing it doing nothing, another Forward being chosen doing nothing, and an opponent's Ability choosing it.

Coverage: **88 implemented / 7 plain / 5 to do** (41, 48, 60, 63, 77).

"""
if "\"When chosen\": Kuja 37" not in s:
    s = s.replace(head, entry, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('CHANGELOG updated')
else:
    print('CHANGELOG already has it')

p = 'AGENTS.md'
s = open(p, encoding='utf-8').read()
anchor = "## Damage goes through Field.cause_damage\n"
note = """## "Chosen" is a targeting event, and it has rules

`Field.notify_targets_chosen()` is called from `Game._on_targets_confirmed` (Assistant.target_complete) — the moment a
session is CONFIRMED, not when rings are clicked. Three conditions:

* once per session (`_chosen_notified`, reset in `request_target`), because picks can be replaced before confirming;
* the chooser (`source_card.controller`) must differ from the card's controller — "chosen by your opponent";
* `targeting_source_kind` must be `Summon` or `Ability`. Set effects never choose, so they must not fire this (same
  line as `cannot_be_chosen`).

The connection is placed AFTER the Stack's `_on_assistant_target_complete` in `game.tscn` on purpose: the triggered
ability must land on top of the Summon/ability that caused it, so it resolves first.

"""
if "## \"Chosen\" is a targeting event" not in s:
    s = s.replace(anchor, note + anchor, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('AGENTS updated')
else:
    print('AGENTS already has it')

for f in ('AGENTS.md', 'CHANGELOG.md'):
    d = open(f, 'rb').read().replace(b'\r\n', b'\n')
    open(f, 'wb').write(d)
