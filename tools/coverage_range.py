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
    # B2 - replacement / shields
    # B3 - targeting / selection (implemented)
    # B4a - cost reductions (177 and 210 implemented)
    # B4b - event triggers (108, 187, 206, 214, 215 implemented)
    173: 'Attack Phase start trigger + element override',
    181: 'return-self-to-hand cost',
    141: 'force a blocker',
    # B5 - complex
    103: 'dynamic element identity',
    107: 'dynamic element identity',
    111: 'variable X cost',
    135: 'multi-card search/play with distinct elements',
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
