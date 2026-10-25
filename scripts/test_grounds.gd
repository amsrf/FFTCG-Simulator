extends RefCounted
## TEST GROUNDS — one board per mechanic, so a feature can be exercised without unrelated cards doing things.
##
## The problem this solves: the `ai` preset is a general practice board, so testing PARTIES there means the AI also
## casts Ifrit and Valefor, and the board changes under you. Each ground below is deliberately narrow — the cards
## that matter, mana only where a cost must be paid, and an opponent that does NOT act unless the mechanic needs it.
##
## Each entry is { title, blurb, config }. `config` is the same dictionary MatchSetup.start_match() consumes, so a
## ground is just a preset with a curated board.
##
## CONVENTIONS:
##   * `opponent_type: "mock"` = the AI passes priority, never plays, never attacks. Use it when YOU are the one
##     exercising the mechanic and you do not want the opponent moving.
##   * `opponent_type: "ai"` = the AI plays and attacks. Use it when the mechanic needs the OTHER seat to act.
##   * Decks start at id 101 so a ground's board cards (usually ids 1-100) are never also in a deck.
##   * No shuffle and seed 0: a ground is the same board every time.

const PLAYER_DECK_START := 101
const OPPONENT_DECK_START := 141
const DECK_SIZE := 30


static func _base() -> Dictionary:
	return {
		"preset": "",
		"opponent_type": "mock",
		"player_deck": range(PLAYER_DECK_START, PLAYER_DECK_START + DECK_SIZE),
		"opponent_deck": range(OPPONENT_DECK_START, OPPONENT_DECK_START + DECK_SIZE),
		"player_hand": [],
		"opponent_hand": [],
		"player_field": [],
		"opponent_field": [],
		"player_graveyard": [],
		"opponent_graveyard": [],
		"player_damage": [],
		"opponent_damage": [],
		"first_phase": "first_main",
		"seed": 0,
		"shuffle": false,
	}


## Card ids used below, named so the grounds read as rules rather than numbers.
const ICE_A := 41        # Squall, ice Forward, no effects
const ICE_B := 43        # Snow,   ice Forward — HAS a when-attack dull effect, so not for the blocking ground
const BARD := 35         # Bard,   ice Forward 4000, no effects — passive, safe to attack with
const DARK_KNIGHT := 55  # Dark Knight, ice Forward 8000, no effects — the intended blocker
const FIRE := 12         # Zack,   fire Forward
const TERRA := 46        # Terra,  ice Forward — raises the OPPONENT's Summon costs by 1, and their Summons cannot choose her
const CHOCOBO := 75      # Chocobo, wind Forward — "forms a party and attacks: party gains +3000"
const HOPE := 82         # Hope,    wind Forward (the second half of the wind pair)
const ZIDANE := 71       # cannot be chosen by the opponent's Summons/abilities
const IFRIT := 4         # Summon: damage a Forward
const BAHAMUT := 18      # Summon: fragile + big damage
const FIRE_MANA := 3     # Red Mage, fire Backup
const ICE_MANA := 31     # Chemist, ice Backup
const ICE_MANA_2 := 32   # Chemist, ice Backup
const WIND_MANA := 68    # Evoker, wind Backup — pays for Thief / Rikku
const MILL_RIKKU := 89   # Rikku: skill 風+dull mills 1; S skill 風+dull mills 2 and draws 1
const MILL_THIEF := 69   # Thief, Forward: enters the field -> opponent mills 1
const MILL_THIEF_BACKUP := 70  # Thief, Backup: same ETB, already on the board here
const SUMMONER := 53     # Summoner: 《Ice》, put itself into the Break Zone: cancel a Summon on the STACK
const CECIL := 108       # Cecil: "When you receive damage, choose 1 Forward opponent controls. You may deal it 5000 damage."
const GILGAMESH := 129   # Gilgamesh: S + Dull, reveal/remove top card, break or damage the chosen Forward.
const GILGAMESH_FORWARD_TOP := 43  # Snow, a Forward: exercises the break branch.
const GILGAMESH_BACKUP_TOP := 31   # Chemist, a Backup: exercises the 3000-damage branch.


static func clean() -> Dictionary:
	## An empty board and no hands: the blank slate, for when a mechanic needs a setup built by hand.
	var cfg: Dictionary = _base()
	cfg["preset"] = "ground_clean"
	return cfg


static func party_you_attack() -> Dictionary:
	## PARTIES, attack side. An ice pair AND a wind pair, so there are two legal parties to build; the opponent has
	## ice and fire Forwards to block with. The opponent is MOCK, so it never plays anything — the only thing that
	## changes is your own attack.
	##
	## The wind pair is Chocobo (75) + Hope (82): Chocobo's "forms a party and attacks" gives the whole party +3000.
	var cfg: Dictionary = _base()
	cfg["preset"] = "ground_party"
	cfg["opponent_type"] = "mock"
	cfg["player_field"] = [
		{"id": ICE_A}, {"id": ICE_B}, {"id": FIRE},
		{"id": CHOCOBO}, {"id": HOPE},
		{"id": ICE_MANA}, {"id": ICE_MANA_2},
	]
	cfg["opponent_field"] = [{"id": ICE_A}, {"id": ICE_B}, {"id": FIRE}]
	cfg["opponent_hand"] = []          # nothing to cast, so no Summons mid-test
	return cfg


static func party_ai_attacks() -> Dictionary:
	## PARTIES, blocking side. The AI holds an ice pair and an EMPTY HAND, so all it does is attack as a party —
	## which is what opens the damage-distribution window when you block it.
	##
	## THE PAIR IS PASSIVE ON PURPOSE. It used to be Squall + Snow, and Snow's "when attacks, dull an opponent's
	## Forward" dulled the only Forward you had left — so the ground whose whole point is blocking you made
	## unblockable. Bard (4000) and Squall (6000) both have no effects at all.
	##
	## Pass your turn once: the AI draws, does nothing in its main phase, then declares the party.
	var cfg: Dictionary = _base()
	cfg["preset"] = "ground_party_ai"
	cfg["opponent_type"] = "ai"
	# Dark Knight (8000) is the intended blocker; Zack is a second option. Mana for the Backups is not needed here.
	cfg["player_field"] = [{"id": DARK_KNIGHT}, {"id": FIRE}, {"id": ICE_MANA}, {"id": ICE_MANA_2}]
	cfg["opponent_field"] = [{"id": BARD}, {"id": ICE_A}]
	cfg["opponent_hand"] = []          # no Ifrit, no Valefor — only the party
	return cfg


static func summons_and_targeting() -> Dictionary:
	## SUMMONS. The AI has one Ifrit and the mana for it; you have Zidane, who cannot be chosen by the opponent's
	## Summons or abilities. Watch the AI struggle to find a legal target.
	var cfg: Dictionary = _base()
	cfg["preset"] = "ground_summons"
	cfg["opponent_type"] = "ai"
	cfg["player_field"] = [{"id": ZIDANE}, {"id": FIRE}]
	cfg["opponent_field"] = [{"id": FIRE_MANA}, {"id": ICE_MANA}, {"id": ICE_MANA_2}]
	cfg["opponent_hand"] = [IFRIT]
	return cfg


static func break_zone() -> Dictionary:
	## THE BREAK ZONE. You hold Bahamut and enough mana; the opponent has two Forwards. Casting it applies fragile
	## and deals 10000 — both Forwards are EXILED instead of broken, so the Break Zone stays empty.
	var cfg: Dictionary = _base()
	cfg["preset"] = "ground_break_zone"
	cfg["opponent_type"] = "mock"
	cfg["player_field"] = [{"id": FIRE_MANA}, {"id": ICE_MANA}, {"id": ICE_MANA_2}, {"id": 68}]
	cfg["player_hand"] = [BAHAMUT]
	cfg["opponent_field"] = [{"id": ICE_A}, {"id": ICE_B}]
	return cfg


## TERRA (46) costs more for YOU: she sits on the opponent's side and her continuous aura adds 1 to the cost of every
## Summon you cast. Ifrit is printed at cost 1 (1 fire), so with her out the payment row must show TWO crystals —
## 1 fire + 1 wild — instead of the single fire crystal you would get on an empty board.
##
## Two fire Backups are on your board: exactly enough to pay the surcharged cost, so the cast itself is still possible
## and you can see it through to the stack.
##
## AND A SECOND FORWARD TO AIM AT. Terra IS a Forward — but she cannot be chosen by the opponent's Summons, so on her
## own the board has no legal Ifrit target: Hand.charge() refuses the cast before payment and the card returns to hand,
## which reads as the surcharge being broken. ICE_A (Squall) is both a legal target and a demonstration that Terra
## herself is not one.
static func terra_cost() -> Dictionary:
	var cfg: Dictionary = _base()
	cfg["preset"] = "ground_terra"
	cfg["opponent_type"] = "mock"
	cfg["player_field"] = [{"id": FIRE_MANA}, {"id": FIRE_MANA}]
	cfg["player_hand"] = [IFRIT]
	cfg["opponent_field"] = [{"id": TERRA}, {"id": ICE_A}]
	return cfg


static func mill() -> Dictionary:
	## MILL. You have Rikku (89) and Thief (70) on the board, three wind Backups to pay for them, and a Thief (69)
	## plus a spare Rikku in hand. Nothing else moves: the opponent is MOCK and its board is empty.
	##
	## Rikku's ability (風 + dull) mills the opponent 1; her S ability discards the Rikku in hand to mill 2 and draw 1.
	## Playing the Thief from hand mills 1 on entry. Both decks are 20 cards so repeated activations stay visible.
	var cfg: Dictionary = _base()
	cfg["preset"] = "ground_mill"
	cfg["opponent_type"] = "mock"
	cfg["player_field"] = [
		{"id": MILL_RIKKU}, {"id": MILL_THIEF_BACKUP},
		{"id": WIND_MANA}, {"id": WIND_MANA}, {"id": WIND_MANA},
	]
	cfg["player_hand"] = [MILL_THIEF, MILL_RIKKU]
	cfg["player_deck"] = range(PLAYER_DECK_START, PLAYER_DECK_START + 20)
	cfg["opponent_deck"] = range(OPPONENT_DECK_START, OPPONENT_DECK_START + 20)
	cfg["opponent_field"] = []
	return cfg


static func counter_summon() -> Dictionary:
	## COUNTERING A SUMMON. You hold the Ifrit and the mana to cast it, plus Summoner (53) and one ice Backup.
	##
	## The whole loop happens on your own turn, in one priority chain:
	##   1. cast Ifrit at the opponent's Squall and CONFIRM the target — it waits on the stack;
	##   2. while it is still there, click Summoner (green ring) and pay the ice;
	##   3. the targeting session now asks for a card ON THE STACK: click the Ifrit and confirm.
	## Ifrit is removed without resolving (Squall takes no damage) and goes to your Break Zone.
	##
	## Countering your own Summon is legal and is the point here: it keeps the demo to one turn and one seat.
	var cfg: Dictionary = _base()
	cfg["preset"] = "ground_counter"
	cfg["opponent_type"] = "mock"
	cfg["player_field"] = [{"id": SUMMONER}, {"id": FIRE_MANA}, {"id": ICE_MANA}, {"id": FIRE}]
	cfg["player_hand"] = [IFRIT]
	cfg["opponent_field"] = [{"id": ICE_A}]
	return cfg


## GILGAMESH 129. There is no CP cost: the ability is S + Dull, so the only setup is a same-name copy in hand
## (the S cost) and a target Forward. The deck top is deliberately known so the reveal branch is deterministic.
## `top_id` chooses which branch this ground demonstrates: a Forward for break, a Backup for 3000 damage.
static func gilgamesh_ground(top_id: int, preset: String) -> Dictionary:
	var cfg: Dictionary = _base()
	cfg["preset"] = preset
	cfg["opponent_type"] = "mock"
	cfg["player_field"] = [{"id": GILGAMESH}]
	cfg["player_hand"] = [GILGAMESH]
	cfg["opponent_field"] = [{"id": ICE_A}]
	cfg["opponent_hand"] = []
	cfg["player_deck"] = [top_id] + range(PLAYER_DECK_START, PLAYER_DECK_START + DECK_SIZE - 1)
	return cfg


static func gilgamesh_reveal_forward() -> Dictionary:
	return gilgamesh_ground(GILGAMESH_FORWARD_TOP, "ground_gilgamesh_forward")


static func gilgamesh_reveal_backup() -> Dictionary:
	return gilgamesh_ground(GILGAMESH_BACKUP_TOP, "ground_gilgamesh_backup")


static func cecil_damage() -> Dictionary:
	## 108 CECIL. Press Y to take 1 damage; Cecil's event trigger asks whether to deal 5000 to an opponent Forward.
	## The three opponent Forwards are deliberately sturdy (6000/7000/8000) so 5000 shows as accumulated damage
	## rather than immediately breaking the target.
	var cfg: Dictionary = _base()
	cfg["preset"] = "ground_cecil"
	cfg["opponent_type"] = "mock"
	cfg["player_field"] = [{"id": CECIL}]
	cfg["player_hand"] = []
	cfg["opponent_field"] = [{"id": ICE_A}, {"id": 47}, {"id": DARK_KNIGHT}]
	cfg["opponent_hand"] = []
	return cfg


const GROUNDS := {
	"party": {
		"title": "Ground: Parties (you attack)",
		"blurb": "Ice pair on both sides. Click Squall then Snow to form a party, then attack. Opponent is passive.",
	},
	"party_ai": {
		"title": "Ground: Parties (AI attacks, you block)",
		"blurb": "Bard + Squall (no triggers) and an EMPTY hand: pass once, it attacks as a party. Block with Dark Knight to open the damage window.",
	},
	"summons": {
		"title": "Ground: Summons & target protection",
		"blurb": "The AI holds Ifrit; your Zidane cannot be chosen by it. Watch who it can target.",
	},
	"break_zone": {
		"title": "Ground: Break Zone & fragile",
		"blurb": "You hold Bahamut and mana. Cast it: fragile + 10000 exiles the targets instead of breaking them.",
	},
	"clean": {
		"title": "Ground: Empty board",
		"blurb": "No cards in play, no hands, seeded decks. A blank slate for setting things up by hand.",
	},
	"mill": {
		"title": "Ground: Mill (cards to the Break Zone)",
		"blurb": "Rikku + Thief on the board and 3 wind Backups. Activate Rikku (風+dull, or her S ability) to mill; play Thief from hand to mill 1 on entry.",
	},
	"terra": {
		"title": "Ground: Terra (Summon cost +1 for you)",
		"blurb": "The opponent has Terra, so your Summons cost 1 more. Play Ifrit and target Squall: the cost row shows 1 fire + 1 wild (2 mana), not the single fire it costs on an empty board.",
	},
	"counter": {
		"title": "Ground: Counter a Summon (targeting the stack)",
		"blurb": "Cast the Ifrit in your hand at Squall and confirm. While it waits on the stack, click Summoner, pay the ice, then click the Ifrit ON THE STACK: it is cancelled and Squall takes no damage.",
	},
	"cecil": {
		"title": "Ground: Cecil 108 (damage received)",
		"blurb": "Press Y to take 1 damage. Cecil may deal 5000 to one opponent Forward: Confirm, then click a target. All three opponent Forwards survive the hit.",
	},
	"gilgamesh_forward": {
		"title": "Ground: Gilgamesh 129 (reveal a Forward)",
		"blurb": "Use Gilgamesh's S + Dull ability; discard the copy in hand. The top card is Snow (Forward), so the chosen Forward is broken. Opponent is passive.",
	},
	"gilgamesh_backup": {
		"title": "Ground: Gilgamesh 129 (reveal a Backup)",
		"blurb": "Use Gilgamesh's S + Dull ability; discard the copy in hand. The top card is Chemist (Backup), so the chosen Forward takes 3000 instead. Opponent is passive.",
	},
}

## No Callable table here: a Dictionary of function references is not a constant expression in GDScript, so the
## dispatch is a plain match. Adding a ground means adding an entry to GROUNDS and one arm below.
static func config(name: String) -> Dictionary:
	match name:
		"party":
			return party_you_attack()
		"party_ai":
			return party_ai_attacks()
		"summons":
			return summons_and_targeting()
		"break_zone":
			return break_zone()
		"clean":
			return clean()
		"mill":
			return mill()
		"terra":
			return terra_cost()
		"counter":
			return counter_summon()
		"cecil":
			return cecil_damage()
		"gilgamesh_forward":
			return gilgamesh_reveal_forward()
		"gilgamesh_backup":
			return gilgamesh_reveal_backup()
		_:
			push_warning("[TestGrounds] no such ground '%s'" % name)
			return clean()


static func names() -> Array:
	return GROUNDS.keys()


static func has(name: String) -> bool:
	return GROUNDS.has(name)


static func title(name: String) -> String:
	return str(GROUNDS.get(name, {}).get("title", name))


static func blurb(name: String) -> String:
	return str(GROUNDS.get(name, {}).get("blurb", ""))



