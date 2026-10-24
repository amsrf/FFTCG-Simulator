"""Card-effect data for the 100-216 push, applied in phases.

Usage:
    python3 tools/card_data_batches.py a1
    python3 tools/card_data_batches.py a2

Each phase ADDS entries to assets/card_effects.json without reformatting the rest of the file, then validates the
result with json.loads. Entries are plain dicts in the same vocabulary the engine already dispatches.
"""
import json
import re
import sys

PATH = 'assets/card_effects.json'


def skill(cost=None, tap=False, s_cost=False, sacrifice=None, choose=None, apply_effect=None,
          instructions=None, text=''):
    d = {}
    if s_cost:
        d['s_cost'] = True
    if tap:
        d['tap'] = True
    d['cost'] = cost if cost is not None else {}
    if sacrifice is not None:
        d['sacrifice'] = sacrifice
    if text:
        d['text'] = text
    if apply_effect is not None:
        d['apply_effect'] = apply_effect
    if choose is not None:
        d['choose_target'] = choose
    d['instructions'] = instructions or []
    return d


def trigger(choose=None, instructions=None, apply_effect=None):
    d = {}
    if apply_effect is not None:
        d['apply_effect'] = apply_effect
    if choose is not None:
        d['choose_target'] = choose
    d['instructions'] = instructions or []
    return d


def ins(name, argument=None, author='game', **extra):
    d = {'name': name, 'author': author, 'argument': argument if argument is not None else []}
    d.update(extra)
    return d


A1 = {
    '112': {
        'when_enter_field': trigger(
            choose={'is_character': True, 'controller': 'player'},
            instructions=[ins('break_targets')]),
        'skill': [skill(
            s_cost=True, cost={'土': 1},
            text="Northswain's Strike 《S》《Earth》: Choose 1 Forward blocking Delita. Break it.",
            choose={'is_type': 'Forward', 'is_blocking': True},
            instructions=[ins('break_targets')])],
    },
    '114': {
        'skill': [skill(
            s_cost=True, cost={'土': 2},
            text='Hammer Blow 《S》《Earth》《Earth》: Choose 1 Forward. Deal it 4000 damage. Barret gains +4000 power until the end of the turn.',
            choose={'is_type': 'Forward'},
            instructions=[ins('damage_targets', [4000]), ins('power_change', [4000, 1], author='card')])],
    },
    '117': {
        'when_cast': trigger(
            choose={'is_type': 'Backup', 'is_cost_at_least': 3},
            instructions=[ins('break_targets')]),
    },
    '118': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward', 'is_tapped': True},
            instructions=[ins('break_targets')]),
    },
    '123': {
        'when_cast': trigger(
            choose={'is_type': 'Forward', 'is_cost_at_most': 4},
            instructions=[ins('break_targets')]),
    },
    '124': {
        'ex_burst': 'when_cast',
        'when_cast': trigger(
            choose={'is_type': 'Forward'},
            instructions=[ins('break_targets')]),
    },
    '126': {
        'apply_effect': {'is_type': 'Forward', 'controller': 'opponent'},
        'when_attack': trigger(instructions=[ins('damage_targets', [3000])]),
        'skill': [skill(
            cost={'雷': 2},
            text='《Lightning》《Lightning》: Orlandeau gains Haste until the end of the turn.',
            instructions=[ins('add_status_effect', ['haste', 1], author='card')])],
    },
    '132': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward', 'controller': 'opponent'},
            instructions=[ins('dull_targets')]),
    },
    '136': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward', 'is_cost_at_most': 2},
            instructions=[ins('break_targets')]),
    },
    '137': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward', 'is_cost_at_most': 3},
            instructions=[ins('break_targets')]),
    },
    '140': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward'},
            instructions=[ins('damage_targets', [5000])]),
    },
    '142': {
        'haste': True,
        'when_enter_field': trigger(
            choose={'is_type': 'Forward', 'controller': 'opponent'},
            instructions=[ins('dull_targets')]),
    },
    '143': {
        'ex_burst': 'when_cast',
        'when_cast': trigger(
            choose={'is_type': 'Forward', 'is_tapped': False},
            instructions=[ins('damage_targets', [5000])]),
    },
    '149': {
        'skill': [
            skill(cost={}, tap=True, sacrifice={'is_type': 'Backup', 'controller': 'player'},
                  text='《Dull》, put 1 Backup into the Break Zone: Choose 1 Forward. Deal it 5000 damage.',
                  choose={'is_type': 'Forward'}, instructions=[ins('damage_targets', [5000])]),
            skill(cost={'雷': 1}, tap=True, s_cost=True,
                  text='Thundaga 《S》《Lightning》《Dull》: Choose 1 Forward. Deal it 10000 damage.',
                  choose={'is_type': 'Forward'}, instructions=[ins('damage_targets', [10000])]),
        ],
    },
    '157': {
        'skill': [skill(
            cost={}, tap=True, sacrifice={'is_source': True},
            text="《Dull》, put Scholar into the Break Zone: Choose 1 Forward you control. Return it to its owner's hand.",
            choose={'is_type': 'Forward', 'controller': 'player'},
            instructions=[ins('return_targets_to_hand')])],
    },
    '161': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward'},
            instructions=[ins('untap_targets')]),
    },
    '170': {
        'ex_burst': 'when_cast',
        'when_cast': trigger(
            choose={'is_type': 'Forward'},
            instructions=[ins('untap_targets'), ins('draw_cards', [1])]),
    },
    '178': {
        'ex_burst': 'when_cast',
        'when_cast': trigger(
            choose={'is_type': 'Forward'},
            instructions=[ins('return_targets_to_hand')]),
    },
    '182': {
        'brave': True,
        'skill': [
            skill(cost={'neutral': 1}, tap=True, s_cost=True,
                  text='Meteorain 《S》《1》《Dull》: Deal 4000 damage to all the Forwards opponent controls.',
                  apply_effect={'is_type': 'Forward', 'controller': 'opponent'},
                  instructions=[ins('damage_targets', [4000])]),
            skill(cost={'neutral': 3}, tap=True, s_cost=True,
                  text='Omnislash 《S》《3》《Dull》: Choose 1 Forward. Break it.',
                  choose={'is_type': 'Forward'}, instructions=[ins('break_targets')]),
        ],
    },
    '186': {
        'first_strike': True,
        'when_enter_field': trigger(
            choose={'is_type': 'Backup'},
            instructions=[ins('break_targets')]),
    },
    '189': {
        'skill': [skill(
            cost={'火': 1}, s_cost=True,
            text='Waterkick 《S》《Fire》: Choose 1 Forward. Dull it and deal it 6000 damage.',
            choose={'is_type': 'Forward'},
            instructions=[ins('dull_targets'), ins('damage_targets', [6000])])],
    },
    '191': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward'},
            instructions=[ins('power_change', [3000, 1], author='target')]),
        'skill': [skill(
            cost={'火': 4}, tap=True, s_cost=True,
            text='Cosmo Memory 《S》《Fire》《Fire》《Fire》《Fire》《Dull》: Deal 6000 damage to all the Forwards opponent controls.',
            apply_effect={'is_type': 'Forward', 'controller': 'opponent'},
            instructions=[ins('damage_targets', [6000])])],
    },
    '192': {
        'on_causing_damage_to_forward': {
            'status': 'raines_mark', 'duration': 1,
            'on_enter_break_zone': [ins('opponent_discards', [1])],
        },
        'when_enter_field': trigger(
            choose={'is_type': 'Forward', 'controller': 'opponent', 'is_tapped': False},
            instructions=[ins('damage_targets', [4000])]),
    },
    '193': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward', 'count': 2},
            instructions=[ins('add_status_to_targets', ['frozen', 1])]),
        'skill': [skill(
            cost={'氷': 1}, tap=True, s_cost=True,
            text='Sadistic Surge 《S》《Ice》《Dull》: Choose 1 Forward. Dull it and Freeze it.',
            choose={'is_type': 'Forward'},
            instructions=[ins('dull_targets'), ins('add_status_to_targets', ['frozen', 1])])],
    },
    '198': {
        'ex_burst': 'when_cast',
        'apply_effect': {'is_type': 'Forward', 'controller': 'opponent'},
        'when_cast': trigger(instructions=[
            ins('damage_targets', [3000]),
            ins('untap_all_matching', [{'is_type': 'Backup', 'controller': 'player'}],
                condition='controls:Yuna'),
        ]),
    },
    '205': {
        'skill': [skill(
            cost={}, s_cost=True,
            text='Grenade Bomb 《S》: Deal 2000 damage to all the Forwards opponent controls.',
            apply_effect={'is_type': 'Forward', 'controller': 'opponent'},
            instructions=[ins('damage_targets', [2000])])],
    },
    '209': {
        'skill': [skill(
            cost={'雷': 1}, tap=True,
            text='《Lightning》《Dull》: Choose 1 attacking Lightning Forward. It gains First Strike until the end of the turn.',
            choose={'is_type': 'Forward', 'is_attacking': True, 'is_element': '雷'},
            instructions=[ins('add_status_to_targets', ['first_strike', 1])])],
    },
    '212': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward', 'controller': 'opponent', 'is_cost_at_most': 3},
            instructions=[ins('return_targets_to_hand')]),
    },
}

A2 = {
    '101': {
        'apply_effect': {'is_type': 'Forward', 'controller': 'player'},
        'when_enter_field': trigger(instructions=[ins('power_change_targets', [4000, 1])]),
    },
    '110': {
        'when_cast': trigger(
            choose={'is_type': 'Forward', 'controller': 'player'},
            instructions=[ins('dull_targets'), ins('add_status_to_targets', ['unbreakable', 1])]),
    },
    '113': {
        'when_blocks': trigger(instructions=[ins('power_change', [2000, 1], author='card')]),
    },
    '115': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward'},
            instructions=[ins('add_status_to_targets', ['brave', 1])]),
    },
    '120': {
        'skill': [skill(
            cost={'土': 1}, tap=True, sacrifice={'is_source': True},
            text='《Earth》《Dull》, put Monk into the Break Zone: Choose 1 Forward. It gains +2000 power until the end of the turn.',
            choose={'is_type': 'Forward'},
            instructions=[ins('power_change', [2000, 1], author='target')])],
    },
    '121': {
        'skill': [skill(
            cost={'雷': 1}, tap=True,
            text='《Lightning》《Dull》: Choose 1 Forward. It gains Haste until the end of the turn.',
            choose={'is_type': 'Forward'},
            instructions=[ins('add_status_to_targets', ['haste', 1])])],
    },
    '134': {
        'when_enter_field': trigger(instructions=[ins('search_deck', [{'job': 'Knight'}])]),
    },
    '144': {
        'power_per': {'count': {'is_type': 'Backup', 'controller': 'player'}, 'value': 1000},
        'skill': [skill(
            cost={'雷': 1}, s_cost=True,
            text='Shout 《S》《Lightning》: Until the end of the turn, Ramza gains +2000 power, Haste and First Strike.',
            instructions=[ins('power_change', [2000, 1], author='card'),
                          ins('add_status_effect', ['haste', 1], author='card'),
                          ins('add_status_effect', ['first_strike', 1], author='card')])],
    },
    '145': {
        'skill': [skill(
            cost={}, tap=True,
            text='《Dull》: Choose 1 Backup. Activate it.',
            choose={'is_type': 'Backup'},
            instructions=[ins('untap_targets')])],
    },
    '146': {
        'skill': [skill(
            cost={'雷': 1}, sacrifice={'is_source': True},
            text='《Lightning》, put Ricard into the Break Zone: Choose 1 Forward. It cannot be broken this turn.',
            choose={'is_type': 'Forward'},
            instructions=[ins('add_status_to_targets', ['unbreakable', 1])])],
    },
    '147': {'first_strike': True},
    '148': {'haste': True},
    '150': {
        'aura': [{'targets': {'is_type': 'Forward', 'controller': 'player', 'is_element': '雷'},
                  'method': 'power_change', 'value': 1000}],
    },
    '156': {
        'aura': [{'targets': {'is_type': 'Forward', 'controller': 'player', 'is_job': 'Knight'},
                  'method': 'power_change', 'value': 1000}],
    },
    '164': {
        'when_attack': trigger(instructions=[
            ins('power_change_matching',
                [{'is_type': 'Forward', 'controller': 'player', 'is_element': '水'}, 1000, 1]),
        ]),
    },
    '167': {'when_enter_field': trigger(instructions=[ins('draw_cards', [1])])},
    '168': {'when_enter_break_from_field': trigger(instructions=[ins('draw_cards', [1])])},
    '179': {'when_cause_damage_to_player': trigger(instructions=[ins('draw_cards', [1])])},
    '180': {
        'aura': [{'targets': {'is_type': 'Forward', 'controller': 'player', 'is_element': '水'},
                  'method': 'power_change', 'value': 1000}],
    },
    '195': {'when_enter_field': trigger(instructions=[ins('opponent_discards', [1])])},
    '196': {
        'when_enter_field': trigger(instructions=[
            ins('search_deck', [{'category': 'XIII', 'type': 'Forward'}])]),
    },
    '197': {
        'when_enter_field': trigger(instructions=[
            ins('search_deck', [{'category': 'X', 'type': 'Forward'}])]),
    },
    '199': {
        'when_enter_field': trigger(
            choose={'is_type': 'Backup', 'controller': 'player', 'count': 3},
            instructions=[
                ins('draw_cards', [1], condition='controls:Yuna'),
                ins('untap_targets', condition='controls:Rikku'),
            ]),
    },
    '200': {
        'skill': [skill(
            cost={}, tap=True, sacrifice={'is_source': True},
            text='《Dull》, put Baralai into the Break Zone: Choose up to 2 Forwards. Activate them.',
            choose={'is_type': 'Forward', 'count': 2},
            instructions=[ins('untap_targets')])],
    },
    '202': {
        'when_attack': trigger(instructions=[ins('add_status_effect', ['first_strike', 1], author='card')]),
    },
    '203': {'when_enter_field': trigger(instructions=[ins('search_deck', [{'name': 'Biggs'}])])},
    '204': {
        'when_enter_field': trigger(instructions=[
            ins('search_deck', [{'category': 'VII', 'type': 'Forward'}])]),
    },
    '208': {
        'haste': True,
        'conditional_power': [{'condition': {'check_controller': 'player', 'is_named': 'Serah'},
                               'value': 2000}],
    },
}

PHASES = {'a1': A1, 'a2': A2}


def format_entry(card_id, entry):
    raw = json.dumps(entry, ensure_ascii=False, indent='\t')
    lines = raw.splitlines()
    out = ['\t"%s": %s' % (card_id, lines[0])]
    out += ['\t' + ln for ln in lines[1:]]
    return '\n'.join(out)


def apply(entries):
    text = open(PATH, encoding='utf-8').read()
    existing = json.loads(text)
    new = {k: v for k, v in entries.items() if k not in existing}
    if len(new) != len(entries):
        print('skipping already-present:', sorted(set(entries) - set(new)))
    if not new:
        print('nothing to add')
        return
    # special fix: card 151 is already present and is missing its printed First Strike
    if '"151":{' in text and '"first_strike"' not in text[text.index('"151":{'):text.index('"when_enter_field"', text.index('"151":{'))]:
        text = text.replace('"151":{\n', '"151":{\n\t\t"first_strike": true,\n', 1)
        print('151: added printed first_strike')

    end = text.rstrip().rfind('}')
    head = text[:end].rstrip()
    if not head.endswith(','):
        head += ','
    block = ',\n'.join(format_entry(k, new[k]) for k in sorted(new, key=int))
    text = head + '\n' + block + '\n}\n'
    json.loads(text)  # raises if the append is malformed
    open(PATH, 'w', encoding='utf-8', newline='\n').write(text)
    print('added %d entries: %s' % (len(new), ', '.join(sorted(new, key=int))))


if __name__ == '__main__':
    phase = sys.argv[1].lower() if len(sys.argv) > 1 else 'a1'
    if phase not in PHASES:
        raise SystemExit('phase must be one of %s' % ', '.join(PHASES))
    apply(PHASES[phase])
