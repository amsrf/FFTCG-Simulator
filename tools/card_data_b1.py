"""B1 data: the 17 cards unlocked by the small engine extensions."""
import card_data_batches as base
from card_data_batches import ins, skill, trigger

B1 = {
    '125': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward', 'is_damaged': True},
            instructions=[ins('damage_targets', [5000])]),
    },
    '130': {
        'skill': [skill(
            cost={'雷': 2}, tap=True, sacrifice={'is_source': True},
            text='《Lightning》《Lightning》《Dull》, put Black Mage into the Break Zone: Choose 1 damaged Forward. Break it.',
            choose={'is_type': 'Forward', 'is_damaged': True},
            instructions=[ins('break_targets')])],
    },
    '172': {
        'ex_burst': 'when_cast',
        'when_cast': trigger(instructions=[ins('draw_cards', [2]), ins('discard_cards', [1])]),
    },
    '190': {
        'ex_burst': 'when_cast',
        'when_cast': trigger(
            choose={'is_type': 'Forward'},
            instructions=[
                ins('discard_cards', [1], may=True, may_prompt='Discard 1'),
                ins('damage_targets', [7000], condition='if_last_succeeded'),
                ins('damage_targets', [5000], condition='if_last_did_not_succeed'),
            ]),
    },
    '153': {
        'self_cost': {'if_controls': {'is_named': 'Ovelia'}, 'delta': -1},
        'skill': [skill(
            cost={}, tap=True,
            text='《Dull》: Draw 1 card, then discard 1 card from your hand.',
            instructions=[ins('draw_cards', [1]), ins('discard_cards', [1])])],
    },
    '133': {
        'when_enter_field': trigger(instructions=[
            ins('break_zone_to_hand', [{'any': [{'type': 'Forward'}, {'type': 'Backup'}]}])]),
    },
    '169': {
        'skill': [skill(
            cost={}, tap=True,
            text='《Dull》: Look at the top card of your deck. You may place it at the bottom of your deck.',
            instructions=[ins('look_top_may_bottom')])],
    },
    '175': {
        'when_enter_field': trigger(instructions=[ins('draw_cards', [1]),
                                                  ins('put_hand_card_on_bottom')]),
    },
    '127': {
        'when_enter_field': trigger(
            choose={'is_type': 'Forward'},
            instructions=[ins('power_change', [-5000, 1], author='target')]),
        'skill': [skill(
            cost={'雷': 2}, tap=True, s_cost=True,
            text="Dragoon's Pride 《S》《Lightning》《Lightning》《Dull》: Choose 1 Forward. Break it. Kain will not activate during your next Active Phase.",
            choose={'is_type': 'Forward'},
            instructions=[ins('break_targets'),
                          ins('add_status_effect', ['skip_next_active', 1], author='card')])],
    },
    '106': {
        'when_cast': trigger(
            choose={'is_type': 'Forward'},
            instructions=[ins('power_change_targets_if_blocking', [2000, 4000, 1])]),
    },
    '194': {
        'when_blocks': trigger(
            choose={'is_type': 'Forward'},
            instructions=[ins('dull_targets')]),
        'skill': [skill(
            cost={'氷': 1}, s_cost=True,
            text='Vendetta 《S》《Ice》: Until the end of the turn, Snow gains +2000 power and First Strike. Use only while Snow is blocking.',
            instructions=[ins('power_change', [2000, 1], author='card'),
                          ins('add_status_effect', ['first_strike', 1], author='card')])],
    },
    '155': {
        'aura': [
            {'targets': {'is_type': 'Forward', 'controller': 'player', 'is_job': 'Standard Unit'},
             'method': 'power_change', 'value': 2000},
            {'targets': {'is_type': 'Forward', 'controller': 'player', 'is_job': 'Standard Unit'},
             'method': 'grant_status', 'status': 'first_strike'},
        ],
    },
    '188': {
        'when_enter_field': trigger(instructions=[ins('search_deck', [{'name': 'Tifa'}])]),
        'aura': [{'targets': {'is_type': 'Forward', 'controller': 'player', 'is_named': 'Tifa',
                              'is_cost_at_most': 4},
                  'method': 'grant_status', 'status': 'haste'}],
    },
    '139': {
        'skill': [skill(
            cost={}, tap=True, sacrifice={'is_source': True},
            text='《Dull》, put Summoner into the Break Zone: Cast 1 Summon of cost 6 or less from your hand without paying its cost.',
            instructions=[ins('cast_summon_for_free',
                              [{'is_type': 'Summon', 'is_cost_at_most': 6}])])],
    },
    '116': {
        'when_blocks': trigger(instructions=[ins('power_change', [4000, 1], author='card')]),
        'skill': [
            skill(cost={'土': 1},
                  text='《Earth》: Prishe gains Brave until the end of the turn.',
                  instructions=[ins('add_status_effect', ['brave', 1], author='card')]),
            skill(cost={'土': 1}, s_cost=True,
                  text='Auroral Uppercut 《S》《Earth》: Double the power of Prishe until the end of the turn.',
                  instructions=[ins('double_power', [1], author='card')]),
        ],
    },
    '128': {
        'skill': [skill(
            cost={'雷': 2}, s_cost=True,
            text='Gilgamesh Morphing Time 《S》《Lightning》《Lightning》: Double its power and gain First Strike and Brave. It can attack twice this turn. Use only during your turn.',
            instructions=[ins('double_power', [1], author='card'),
                          ins('add_status_effect', ['first_strike', 1], author='card'),
                          ins('add_status_effect', ['brave', 1], author='card'),
                          ins('set_extra_attacks', [1], author='card')])],
    },
    '163': {
        'power_per': {'count': {'is_type': 'Forward', 'controller': 'player',
                                'exclude': {'is_source': True}}, 'value': 1000},
        'skill': [skill(
            cost={'水': 2}, s_cost=True,
            text='Blitz Ace 《S》《Water》《Water》: Until the end of the turn Tidus gains Brave. Tidus can attack as many times as your points of damage this turn.',
            instructions=[ins('add_status_effect', ['brave', 1], author='card'),
                          ins('extra_attacks_from_damage')])],
    },
}

if __name__ == '__main__':
    base.apply(B1)
