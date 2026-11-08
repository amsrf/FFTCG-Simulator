import re
import os

FIELD_NAMES = {
    "text", "cost", "tap", "s_cost", "discard", "sacrifice", "divide_total",
    "return_self", "targets", "target_count", "target_chooser", "target_timing",
    "only_your_turn", "only_if_blocking", "only_if_damage_received",
    "once_per_turn", "copied", "free_activation", "copied_from",
}


def matching(text, start, open_ch, close_ch):
    depth = 0
    quote = ""
    esc = False
    for i in range(start, len(text)):
        ch = text[i]
        if quote:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == quote:
                quote = ""
            continue
        if ch in ('"', "'"):
            quote = ch
        elif ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return i
    return -1


def split_top(text):
    out = []
    start = 0
    depth = 0
    quote = ""
    esc = False
    for i, ch in enumerate(text):
        if quote:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == quote:
                quote = ""
            continue
        if ch in ('"', "'"):
            quote = ch
        elif ch in "{[(":
            depth += 1
        elif ch in "}])":
            depth -= 1
        elif ch == "," and depth == 0:
            out.append(text[start:i])
            start = i + 1
    tail = text[start:]
    if tail.strip():
        out.append(tail)
    return out


def first_colon(text):
    depth = 0
    quote = ""
    esc = False
    for i, ch in enumerate(text):
        if quote:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == quote:
                quote = ""
            continue
        if ch in ('"', "'"):
            quote = ch
        elif ch in "{[(":
            depth += 1
        elif ch in "}])":
            depth -= 1
        elif ch == ":" and depth == 0:
            return i
    return -1


def parse_ability(block):
    fields = {}
    run_method = ""
    for entry in split_top(block):
        entry = entry.strip()
        if not entry:
            continue
        colon = first_colon(entry)
        if colon < 0:
            continue
        key = entry[:colon].strip().strip('"')
        value = entry[colon + 1:].strip()
        if key == "run":
            m = re.search(r'Callable\(self,\s*"([^"]+)"\)', value)
            if m:
                run_method = m.group(1)
            else:
                raise ValueError("unsupported run value: " + value[:80])
            continue
        fields[key] = value
    return fields, run_method


for name in sorted(os.listdir("assets/effects")):
    if not name.startswith("card_") or not name.endswith(".gd") or name == "card_181.gd":
        continue
    path = os.path.join("assets/effects", name)
    s = open(path, encoding="utf-8").read()
    if "_ability({" not in s:
        continue
    marker = "func activated_abilities() -> Array:"
    start = s.index(marker)
    body_start = start + len(marker)
    # Find the next top-level function/class after the activated_abilities body.
    tail = s[body_start:]
    # simpler: next line starting at column 0 with func/class/const/var
    lines = tail.splitlines(keepends=True)
    offset = body_start
    end = len(s)
    for line in lines:
        if line.strip() and not line.startswith(("\t", " ")) and line.startswith(("func ", "class ", "const ", "var ", "static var ")):
            end = offset
            break
        offset += len(line)
    body = s[body_start:end]

    abilities = []
    cursor = 0
    while True:
        i = body.find("_ability(", cursor)
        if i < 0:
            break
        close = matching(body, i + len("_ability(") - 1, "(", ")")
        if close < 0:
            raise ValueError("unbalanced ability in " + name)
        call = body[i:close + 1]
        ob = call.find("{")
        if ob < 0:
            raise ValueError("no dict in " + name)
        cb = matching(call, ob, "{", "}")
        block = call[ob + 1:cb]
        abilities.append(parse_ability(block))
        cursor = close + 1

    if not abilities:
        continue

    returns = ", ".join("Ability%d.new(self)" % i for i in range(len(abilities)))
    replacement = marker + "\n\treturn [" + returns + "]\n"
    s = s[:start] + replacement + s[end:]

    classes = []
    for i, (fields, run_method) in enumerate(abilities):
        lines = ["", "class Ability%d extends \"res://scripts/effects/card_ability.gd\":" % i,
                 "\tfunc _init(owner = null) -> void:",
                 "\t\tsuper(owner)"]
        for key, value in fields.items():
            if key in FIELD_NAMES:
                lines.append("\t\t%s = %s" % (key, value))
        if run_method:
            lines += ["", "\tfunc on_resolve(ctx) -> void:",
                      "\t\tawait _owner.%s(ctx)" % run_method]
        classes.append("\n".join(lines))
    s = s.rstrip("\n") + "\n" + "\n".join(classes) + "\n"
    open(path, "w", encoding="utf-8", newline="\n").write(s)

print("converted ability cards")
