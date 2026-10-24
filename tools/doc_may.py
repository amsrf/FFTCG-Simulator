p = 'CHANGELOG.md'
s = open(p, encoding='utf-8').read()
head = "## [Unreleased] — 2026-09-11\n"
entry = head + """
### "You may" is a real choice — Squall 41, Leon 60, Vaan 63

The last three cards needed one shared idea: **may is decided at resolution, after targets are locked**, and it is a
decision the player can decline.

* `may` on an instruction, plus `may_by` and `may_prompt`. The gate sits in `_process_next_instruction`, at the moment
  the instruction is reached: the controller's agent is asked (or the OPPONENT's, with `may_by: "opponent"`).
* A refusal is a normal no-op: the rest of the chain continues and `if_last_did_not_succeed` sees it, so an else-branch
  can key off it.
* `LocalAgent.confirm_optional()` shows **Confirm** and **Refuse**. The short prompt is the CONFIRM BUTTON'S TEXT
  ("Deal 6000", "Play a Character"), which is the only message surface the rack has — and it keeps the buttons short.

Card work:

* **41 Squall** — `when_blocks` and `when_blocked`, both queued at the DECLARATION (the single moment both become
  true; a party means every member is blocked), choose 1 Forward, `may` deal 6000. Renzokuken is an S ability with an
  ice mana cost and grants Squall First Strike until end of turn.
* **60 Leon** — the OPPONENT decides (`may_by`), and the free play comes from THEIR hand (`play_from_hand(..., "opponent")`).
* **63 Vaan** — may play a Wind Forward of cost 3 or less from hand; when it attacks, choose up to 2 Backups you
  control and activate them.

`Game.play_from_hand(criteria, by)` plays for free (no cost — the text says PLAY, not CAST), through the same search
window (`Agent.choose_hand_card_to_play`), and `Hand.remove_for_play()` stops the hand owning the card before
`Field.play_card()` takes it. The returning card is reset by `Card.reset_for_field_arrival()`.

New probe `may_probe` (26 checks): accept and decline on a bare instruction, Squall's 6000 with both answers, the
block declaration firing `when_blocked`, both free-play cases (controller and opponent), the two-Backup attack
trigger, Renzokuken's self First Strike, and the real Confirm/Refuse buttons appearing and clearing.

**Card coverage for ids 1-100 is complete: 93 implemented / 7 with no text / 0 to do.**

"""
if "### \"You may\" is a real choice" not in s:
    s = s.replace(head, entry, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('CHANGELOG updated')
else:
    print('CHANGELOG already has it')

p = 'AGENTS.md'
s = open(p, encoding='utf-8').read()
anchor = "## Damage goes through Field.cause_damage\n"
note = """## "May" is an instruction flag, decided at resolution

`may: true` on an instruction makes the controller choose when the instruction is REACHED — after targets are locked,
which is the rule. `may_by: "opponent"` gives the choice to the other player (Leon 60); `may_prompt` is the confirm
button's text. A refusal skips the instruction, sets `_last_action_succeeded = false`, and the chain continues.

`LocalAgent.confirm_optional()` shows Confirm / Refuse through Assistant.show_modal. Answers live on members, not
lambdas — GDScript lambdas capture locals by value.

Block triggers are queued by `Game.set_blocker()`: the blocker's `when_blocks`, and `when_blocked` for EVERY attacking
party member. Declaration is the single moment both become true.

`play_from_hand` plays for free — no mana, no charge; call `Hand.remove_for_play()` and then
`Card.reset_for_field_arrival()` before `Field.play_card()`.

"""
if "## \"May\" is an instruction flag" not in s:
    s = s.replace(anchor, note + anchor, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('AGENTS updated')
else:
    print('AGENTS already has it')

for f in ('AGENTS.md', 'CHANGELOG.md'):
    d = open(f, 'rb').read().replace(b'\r\n', b'\n')
    open(f, 'wb').write(d)
