"""Dump the effect text of the first N cards, clean of markup, so they can be bucketed by what the engine
can already express. Run from the repo root:  python3 tools/dump_effects.py [count]"""
import json
import re
import sys

COUNT = int(sys.argv[1]) if len(sys.argv) > 1 else 100


def clean(text):
    text = re.sub(r"\[\[br\]\]", " ", text or "")
    text = re.sub(r"\[/?[a-z]\]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def main():
    with open("assets/card_database.json", encoding="utf-8") as f:
        cards = json.load(f)["cards"]
    for i in range(min(COUNT, len(cards))):
        card = cards[i]
        text = clean(card.get("text_en", ""))
        if not text:
            continue
        print("%3d | %-9s %-3s %-30s | %s" % (
            i + 1,
            card.get("code", ""),
            (card.get("type_en", "") or "")[:3],
            (card.get("name_en", "") or "")[:30],
            text[:200],
        ))


if __name__ == "__main__":
    main()
