#!/usr/bin/env python3
"""Check every coded activated ability's `text` against the PRINTED card.

The stack card and the ability picker show `AbilitySpec.text` (minus its cost, AbilitySpec.stack_wording), so a text
copied from the wrong printed ability puts the wrong words on the stack while the effect itself is right. Aerith 64's
Planet Protector carried her enter-the-field sentence; a plain "is it somewhere in the printed text" check cannot see
that, because the sentence IS printed - just in another ability. So each coded ability is matched against the printed
ACTIVATED abilities only (a [[br]] line with a cost before a colon, not "When / Each time / At the").

  python3 tools/ability_text_check.py          # report
  python3 tools/ability_text_check.py --fix    # rewrite each mismatched `text = "..."` to the printed wording

It also reports a cost mismatch it can see from the text alone: a printed 《Dull》 that the code does not charge
(`tap = true`), or the reverse. Those are rules bugs, not wording, and are never auto-fixed.
"""
import difflib
import glob
import json
import re
import sys

ELEMENTS = {"火": "Fire", "氷": "Ice", "風": "Wind", "土": "Earth", "雷": "Lightning", "水": "Water",
	"光": "Light", "闇": "Dark", "ダル": "Dull"}
OPENINGS = ("When ", "Each time ", "At the ")


def load_db():
	data = json.load(open("assets/card_database.json"))
	cards = data if isinstance(data, list) else data.get("cards", data)
	items = cards.values() if isinstance(cards, dict) else cards
	return {int(c["id"]): c for c in items if isinstance(c, dict) and "id" in c}


def clean(text):
	"""Printed markup -> the plain wording the game shows."""
	t = re.sub(r"\[\[s\]\]\s*(.*?)\s*\[\[/\]\]\s*", r"\1 ", text)
	t = re.sub(r"\[\[ex\]\].*?\[\[/\]\]", "", t)
	t = re.sub(r"\[\[/?[a-z]*\]\]", "", t)
	t = re.sub(r"\[Card Name \(([^)]*)\)\]", r"\1", t)
	t = re.sub(r"\[Category \(([^)]*)\)\]", r"Category \1", t)
	t = re.sub(r"\[Job \(([^)]*)\)\]", r"Job \1", t)
	for k, v in ELEMENTS.items():
		t = t.replace("《%s》" % k, "《%s》" % v)
	return re.sub(r"\s+", " ", t).strip()


def activated(printed):
	"""The printed activated abilities: a cost before a colon, not an auto-ability."""
	out = []
	for line in printed.split("[[br]]"):
		line = clean(line)
		if not line or line.startswith(OPENINGS) or ":" not in line:
			continue
		cost = line.split(":", 1)[0]
		if "《" in cost or cost.lower().startswith(("dull", "put ", "remove ", "return ")):
			out.append(line)
	return out


def split(text):
	"""(name, cost, effect). The name is the S ability's name in front of 《S》."""
	cost, _, effect = text.partition(":")
	name = ""
	m = re.match(r"^(.*?)\s*《S》", cost)
	if m:
		name = m.group(1).strip()
	return name, cost.strip(), effect.strip()


def norm(s):
	return re.sub(r"[^a-z0-9 ]", "", re.sub(r"\s+", " ", s.lower())).strip()


def best_match(code_text, candidates):
	name, _, effect = split(code_text)
	if name:
		for c in candidates:
			if split(c)[0].lower() == name.lower():
				return c
	scored = [(difflib.SequenceMatcher(None, norm(effect), norm(split(c)[2])).ratio(), c) for c in candidates]
	scored.sort(reverse=True)
	return scored[0][1] if scored else None


def main():
	fix = "--fix" in sys.argv
	db = load_db()
	wrong = 0
	cost_issues = 0
	for path in sorted(glob.glob("assets/effects/card_*.gd")):
		cid = int(re.search(r"card_(\d+)", path).group(1))
		src = open(path).read()
		printed = activated(db.get(cid, {}).get("text_en", ""))
		new_src = src
		# Each Ability class: its text line and (optionally) a `tap = true` line in the same class body.
		for cls in re.finditer(r"^class \w+ extends [^\n]*card_ability\.gd\":\n(.*?)(?=^class |\Z)", src, re.M | re.S):
			body = cls.group(1)
			m = re.search(r'^(\s*)text = "((?:[^"\\]|\\.)*)"', body, re.M)
			if m is None:
				continue
			code_text = m.group(2)
			if not printed:
				print("%d: no printed activated ability to match %r" % (cid, code_text))
				continue
			match = best_match(code_text, printed)
			if match is None:
				continue
			if norm(split(code_text)[2]) != norm(split(match)[2]) or norm(split(code_text)[0]) != norm(split(match)[0]):
				wrong += 1
				print("%d %s\n   code:    %s\n   printed: %s" % (cid, db[cid]["name_en"], code_text, match))
				if fix:
					new_src = new_src.replace('text = "%s"' % code_text, 'text = "%s"' % match.replace('"', '\\"'), 1)
			taps = re.search(r"^\s*tap = true", body, re.M) is not None
			printed_taps = "《Dull》" in split(match)[1]
			if taps != printed_taps:
				cost_issues += 1
				print("%d %s: COST - printed %s 《Dull》, code tap = %s" % (cid, db[cid]["name_en"],
					"has" if printed_taps else "has no", taps))
		if fix and new_src != src:
			open(path, "w").write(new_src)
	print("wording mismatches: %d%s | dull-cost mismatches: %d" % (wrong, " (fixed)" if fix else "", cost_issues))


if __name__ == "__main__":
	main()
