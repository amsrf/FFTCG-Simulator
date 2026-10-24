"""Coverage/classification for the 100-216 card push.

Every id must fall in exactly one bucket:
  * implemented  - has an entry in assets/card_effects.json
  * vanilla      - no rules text
  * needs code   - listed in NEEDS_CODE with the primitive it is waiting on
Anything else is a gap and `--check` exits non-zero.

Usage:
    python3 tools/coverage_range.py
    python3 tools/coverage_range.py --check
"""
import json
import sys

FIRST, LAST = 100, 216

VANILLA = {105, 119, 138, 159}

# Cards that cannot be expressed with today's vocabulary, grouped by the primitive they need.
# Move an id out of here when it lands (the "implemented" bucket is read from the JSON, so an entry wins).
NEEDS_CODE = {
    # B1 - tiny vocabulary
    125: 'is_damaged predicate',
    130: 'is_damaged predicate',
    172: 'discard_cards(n) instruction',
    190: 'discard_cards(n) instruction + may',
    153: 'discard instruction + conditional cost',
    133: 'Break Zone -> hand instruction',
    169: 'look at top card / put on bottom',
    175: 'draw + put a hand card on the bottom',
    127: 'skip next Active Phase status',
    106: 'conditional power while blocking',
    194: 'only-if-blocking skill condition',
    155: 'aura granting First Strike',
    188: 'grant Haste to matching cards',
    139: 'cast a Summon for free',
    116: 'double power',
    128: 'double power + attack twice',
    163: 'attack multiple times',
    # B2 - replacement / shields
    152: 'Forwards enter the field dull',
    160: 'next damage becomes 0',
    165: 'party member damage becomes 0',
    166: 'party member damage becomes 0',
    171: 'damage below power becomes 0',
    176: 'exile instead of Break Zone',
    # B3 - targeting / selection
    162: 'forced targeting',
    174: 'forced targeting',
    201: 'conditional cannot-be-chosen',
    109: 'each player selects from their Break Zone',
    158: 'each player selects; break the rest',
    185: 'search and play onto the field dull',
    207: 'cannot be returned + damage-count condition',
    # B4 - costs / triggers
    177: 'cost_aura with an element filter',
    187: 'cost reduction per Category count + global attack buff',
    210: 'cost reduction per Category count',
    213: 'cost reduction per Category count + Yuna-leaves trigger',
    214: 'when-you-cast-a-Summon trigger (once per turn)',
    215: 'when-opponent-casts-a-Summon trigger',
    206: 'when a Backup you control leaves the field',
    211: 'targeted on-break rider',
    173: 'Attack Phase start trigger + element override',
    181: 'return-self-to-hand cost',
    129: 'exile top card and branch on its type',
    131: 'exile top card and branch on its type',
    141: 'force a blocker',
    # B5 - complex
    102: 'copy an opponent Forward ability',
    103: 'dynamic element identity',
    107: 'dynamic element identity',
    104: 'delayed break at end of turn',
    108: 'when you receive damage trigger',
    111: 'variable X cost',
    135: 'multi-card search/play with distinct elements',
    183: 'any-element mana production',
    184: 'any-element mana production',
    216: 'dynamic power + strip abilities / set power 1000',
}


def main():
    db = json.load(open('assets/card_database.json', encoding='utf-8'))['cards']
    eff = json.load(open('assets/card_effects.json', encoding='utf-8'))

    implemented, vanilla, missing, gaps, conflicts = [], [], [], [], []
    for i in range(FIRST, LAST + 1):
        has_entry = str(i) in eff
        if has_entry:
            implemented.append(i)
            if i in NEEDS_CODE:
                # fine: it landed early (or partially), but say so so the list stays honest
                conflicts.append(i)
        elif i in VANILLA:
            vanilla.append(i)
        elif i in NEEDS_CODE:
            missing.append(i)
        else:
            gaps.append(i)

    print('cards %d-%d: %d total' % (FIRST, LAST, LAST - FIRST + 1))
    print('  implemented : %d' % len(implemented))
    print('  vanilla     : %d' % len(vanilla))
    print('  needs code  : %d' % len(missing))
    print('  UNCLASSIFIED: %d %s' % (len(gaps), gaps if gaps else ''))
    if conflicts:
        print('  note: entries already present for needs-code ids: %s' % conflicts)

    by_reason = {}
    for i in missing:
        by_reason.setdefault(NEEDS_CODE[i], []).append(i)
    print('\nneeds-code groups:')
    for reason in sorted(by_reason):
        print('  %-55s %s' % (reason + ':', by_reason[reason]))

    if '--check' in sys.argv:
        if gaps:
            print('\nCHECK FAILED: unclassified ids %s' % gaps)
            sys.exit(1)
        print('\nCHECK OK: every id is implemented, vanilla, or explicitly needs code')
    return 0


if __name__ == '__main__':
    sys.exit(main() or 0)
