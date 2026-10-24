"""Audit every function in scripts/game.gd for call sites.

For each function it looks for:
  * direct calls            name( ... )            — in .gd / .tscn / .tres
  * bare method references   tween_callback(name)   — the Callable form
  * quoted references        "name"                 — dynamic call("name"), scene method="name", and the
                                                      effect JSON, which invokes instructions by the action name
and reports who the users are: production code, tests/tools, or data.

Categories printed: UNREFERENCED, TEST-ONLY, QUOTED-ONLY, DATA-ONLY.
Instruction handlers (damage_targets, draw_cards, ...) are DATA entries: they are called by name from
assets/card_effects.json through the instruction chain, which is why a plain grep of .gd files finds no caller.

Run: python3 tools/game_dead_audit.py
"""
import os
import re
from collections import Counter

ROOT = '.'
SKIP = ('.git', '.godot', 'addons')
TARGET = 'scripts/game.gd'

files = []
for base, dirs, names in os.walk(ROOT):
    if any(part in base for part in SKIP):
        continue
    for n in names:
        if n.endswith(('.gd', '.tscn', '.tres', '.json')):
            p = os.path.join(base, n).replace('\\', '/')
            if p.startswith('./'):
                p = p[2:]
            files.append(p)

texts = {f: open(f, encoding='utf-8', errors='ignore').read() for f in files}
src = texts[TARGET]
funcs = []
for m in re.finditer(r'^func\s+([A-Za-z_]\w*)\s*\(', src, re.M):
    funcs.append((m.group(1), src[:m.start()].count('\n') + 1))

ENGINE = {'_ready', '_process', '_physics_process', '_input', '_unhandled_input',
          '_unhandled_key_input', '_notification', '_enter_tree', '_exit_tree', '_draw'}


def bucket(items):
    prod, tst, data = [], [], []
    for f, i in items:
        if f.endswith('.json'):
            data.append((f, i))
        elif f.startswith(('tests/', 'tools/')):
            tst.append((f, i))
        else:
            prod.append((f, i))
    return prod, tst, data


def classify(name, def_line):
    direct, quoted, bare = [], [], []
    pat_direct = re.compile(r'(?<![\w.])' + re.escape(name) + r'\s*\(|\.' + re.escape(name) + r'\s*\(')
    pat_quoted = re.compile(r'["\']' + re.escape(name) + r'["\']')
    pat_bare = re.compile(r'\b' + re.escape(name) + r'\b')
    for f, txt in texts.items():
        for i, ln in enumerate(txt.splitlines(), start=1):
            if f == TARGET and i == def_line:
                continue
            if pat_direct.search(ln):
                direct.append((f, i))
            if pat_quoted.search(ln):
                quoted.append((f, i))
            # bare Callable reference: remove comments and string literals first, so prose and
            # quoted names do not count as code references
            code = re.sub(r'"[^"]*"|\'[^\']*\'', '', ln.split('#', 1)[0])
            if pat_bare.search(code):
                bare.append((f, i))
    return bucket(direct), bucket(quoted), bucket(bare)


def is_connected_handler(name):
    pat = re.compile(r'method="' + re.escape(name) + r'"|connect\(\s*(Callable\([^)]*,\s*)?["\']' +
                     re.escape(name) + r'["\']|set_[a-z_]*button\(\s*' + re.escape(name) + r'\b')
    return any(pat.search(txt) for f, txt in texts.items() if not f.endswith('.json'))


rows = []
for name, line in funcs:
    (d_prod, d_tst, d_data), (q_prod, q_tst, q_data), (b_prod, b_tst, b_data) = classify(name, line)
    direct_prod = d_prod
    prod = sorted(set(d_prod) | set(b_prod) | set(q_prod))
    tst = sorted(set(d_tst) | set(b_tst) | set(q_tst))
    data = sorted(set(d_data) | set(q_data) | set(b_data))
    if name in ENGINE:
        status = 'engine hook'
    elif name.startswith('_on_') and is_connected_handler(name):
        status = 'scene/code connected'
    elif not prod and not tst and not data:
        status = 'UNREFERENCED'
    elif not prod and data:
        status = 'DATA-ONLY'
    elif not prod:
        status = 'TEST-ONLY'
    elif not direct_prod:
        status = 'QUOTED-ONLY'
    else:
        status = 'called'
    rows.append((status, name, line, prod, tst, data))

print('game.gd functions:', len(funcs))
for status in ('UNREFERENCED', 'TEST-ONLY', 'QUOTED-ONLY', 'DATA-ONLY'):
    print('\n=== %s ===' % status)
    for st, name, line, prod, tst, data in rows:
        if st != status:
            continue
        print('  %-40s line %-5d prod=%-2d test=%-2d data=%-2d' % (name, line, len(prod), len(tst), len(data)))
        for f, i in (prod + tst + data)[:3]:
            print('        %s:%d' % (f, i))

print('\n=== summary ===')
print(Counter(r[0] for r in rows))
