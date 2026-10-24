p = 'CHANGELOG.md'
s = open(p, encoding='utf-8').read()
head = "## [Unreleased] — 2026-09-11\n"
entry = head + """
### The Break Zone search: Devout 48 / 77

The deck search window now serves a second zone — literally the same scene and the same fan, with an optional
subtitle (`DeckSearch.open(ids, filter, subtitle_text)`). That reuse is the point: a card must read the same way
wherever it is inspected, and a second viewer would drift.

* `Agent.choose_break_zone_card(owner_id, ids, filter)` is the seam. `LocalAgent` opens the window; the default (AI,
  mock, remote) takes the first, so an instruction awaiting a choice can never hang.
* `Game.play_from_break_zone(criteria)` is the instruction: collect the pile's matching cards, ask, remove the chosen
  one from the pile, and `Field.play_card()` it (history, sickness, ETB and the field row all follow automatically).
* `Card.reset_for_field_arrival()` — a card returning from a non-field zone is a NEW permanent: damage, statuses and
  temporary buffs are cleared, it is untapped and not broken. Clearing `power_array` alone would have left the bonus
  baked into `power`, which is a running value.
* `only_your_turn` on a skill closes Devout 48's ability outside its controller's turn, checked per ability in both
  `can_activate_now` (the green ring / gate) and the multi-skill picker.

New probe `devout_probe` (19 checks): only legal cards offered, the Break Zone subtitle, the card reaching the field and
leaving the pile, damage/status reset, summoning sickness, no window when nothing is legal, and the turn gate.

Coverage: **90 implemented / 7 plain / 3 to do** (41, 60, 63).

"""
if "### The Break Zone search: Devout 48 / 77" not in s:
    s = s.replace(head, entry, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('CHANGELOG updated')
else:
    print('CHANGELOG already has it')

p = 'AGENTS.md'
s = open(p, encoding='utf-8').read()
anchor = "## \"Chosen\" is a targeting event, and it has rules\n"
note = """## A zone picker is the deck search, not a new window

`DeckSearch.open(ids, filter, subtitle_text)` is reused for the Break Zone (Devout 48/77). Pass the zone label through
the subtitle; do not build a second viewer.

The choice goes through the agent seam (`Agent.choose_break_zone_card`), so a human gets the window and an AI/mock/remote
answers without one — an instruction awaiting a pick must never hang.

A card RETURNING from a non-field zone is a NEW permanent: call `Card.reset_for_field_arrival()`. It subtracts the
remaining `power_array` buffs from the running `power` before clearing them (clearing the list alone bakes the bonus
in), clears statuses and damage, untaps and unsets `broken`.

Per-ability time gates (`only_your_turn`) must be checked in BOTH `can_activate_now` and the multi-skill picker's
usable list, or the green ring and the picker disagree.

"""
if "## A zone picker is the deck search" not in s:
    s = s.replace(anchor, note + anchor, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('AGENTS updated')
else:
    print('AGENTS already has it')

for f in ('AGENTS.md', 'CHANGELOG.md'):
    d = open(f, 'rb').read().replace(b'\r\n', b'\n')
    open(f, 'wb').write(d)
