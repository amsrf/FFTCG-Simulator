p = 'CHANGELOG.md'
s = open(p, encoding='utf-8').read()
head = "## [Unreleased] — 2026-09-11\n"
entry = head + """
### Damage riders and a status that remembers: Cid 72/73

`Field.cause_damage(target, amount, source, kind, controller)` is now the SINGLE place damage lands, and every path
goes through it: effect damage (`damage_targets`, `damage_forward`), combat (`clash_cards`, `clash_step`), party
damage and the blocker's split. A dealer can therefore attach a rider without any call site knowing about it:

```json
"on_causing_damage_to_forward": {
  "status": "cid_verdict",
  "duration": 1,
  "on_break": [ {"name": "opponent_mills", "author": "game", "argument": [2]} ]
}
```

The rider is stored ON THE DAMAGED FORWARD as a status whose value is a PAYLOAD (`{duration, controller, on_break}`),
not a bare number. That is the key decision: it survives Cid leaving play, it remembers which player's opponent mills
later, and it is one-turn for free — `Card.turn_end()` now expires payload statuses as well as numeric ones.

When the marked card reaches the Break Zone, the same choke point as the printed Break Zone keywords
(`trigger_break_zone_keywords`, gated to field → Break Zone) runs the payload ONCE and erases it.

72 also gets its S ability: 《S》《Dull》 → opponent mills 2.

New probe `cid_probe` (11 checks): no rider on a Backup, the mark and its recorded controller, nothing happening while
the Forward lives, exactly 2 milled when it breaks, the rider consumed, and the expiry case milling nothing later.

Coverage: **87 implemented / 7 plain / 6 to do**.

"""
if "### Damage riders and a status that remembers" not in s:
    s = s.replace(head, entry, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('CHANGELOG updated')
else:
    print('CHANGELOG already has it')

p = 'AGENTS.md'
s = open(p, encoding='utf-8').read()
anchor = "## Rules live in scripts/rules.gd, not in Field\n"
note = """## Damage goes through Field.cause_damage

Do NOT call `card.suffer_damage()` for game damage. `Field.cause_damage(target, amount, source, kind, controller)`
applies `modify_damage`, lands the damage, and runs the dealer's `on_causing_damage_to_forward` riders. Every path
(effect damage, combat, first strike, party damage, blocker split) already uses it; a new damage path must too or
riders silently stop applying.

A status can be a DICTIONARY payload: `{duration, controller, on_break}`. `Card.turn_end()` expires it like a number,
and `Game.trigger_break_zone_keywords()` runs `on_break` once when the card reaches the Break Zone from the field. Use
this shape when a trigger has to remember something about the card it is attached to (Cid 72/73's "the Forward that
took damage from Cid").

"""
if "## Damage goes through Field.cause_damage" not in s:
    s = s.replace(anchor, note + anchor, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('AGENTS updated')
else:
    print('AGENTS already has it')

for f in ('AGENTS.md', 'CHANGELOG.md'):
    d = open(f, 'rb').read().replace(b'\r\n', b'\n')
    open(f, 'wb').write(d)
