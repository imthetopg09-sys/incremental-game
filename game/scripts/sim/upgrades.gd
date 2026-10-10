class_name Upgrades
extends RefCounted
## The Lamp Tree (bought with Tallow between nights) and the Boons (drafted on
## level-ups during a night). Pure data plus the math that turns levels into stats.

const TREE := [
	{"id": "thick_wick", "name": "Thick Wick", "desc": "+25% flame", "costs": [20, 45, 90, 165, 270]},
	{"id": "wide_glow", "name": "Wide Glow", "desc": "+10% light radius for every lantern", "costs": [30, 60, 120, 210, 330]},
	{"id": "hot_flame", "name": "Hot Flame", "desc": "+20% burn for every lantern and Boon", "costs": [30, 70, 135, 240, 375]},
	{"id": "rendering_vat", "name": "Rendering Vat", "desc": "+30% Tallow", "costs": [45, 105, 210, 390]},
	{"id": "extra_sconce", "name": "Extra Sconce", "desc": "+1 Sconce to keep another Echo", "costs": [90, 240]},
	{"id": "foresight", "name": "Foresight", "desc": "See +1 s further down each Echo's path", "costs": [15, 40, 75]},
	{"id": "afterglow", "name": "Afterglow", "desc": "Spent Echoes linger as lamps for 3 / 6 / 10 s", "costs": [60, 135, 270]},
	{"id": "kindling", "name": "Kindling", "desc": "Start each night with 1 / 2 / 3 Boons", "costs": [75, 180, 360]},
]

const AFTERGLOW_SECONDS := [0.0, 3.0, 6.0, 10.0]

const BOONS := [
	{"id": "flare", "name": "Flare", "desc": "Fires a homing bolt at the nearest shadow"},
	{"id": "moths", "name": "Moths", "desc": "Moths circle your lantern and burn what they touch"},
	{"id": "candle", "name": "Dripping Candle", "desc": "Leaves a trail of burning wax"},
	{"id": "spark", "name": "Chain Spark", "desc": "Lightning that jumps between shadows"},
]
const BOON_MAX_LEVEL := 5


static func node(id: String) -> Dictionary:
	for n in TREE:
		if n["id"] == id:
			return n
	return {}


static func max_level(id: String) -> int:
	return node(id).get("costs", []).size()


## Cost of the next level, or -1 when maxed.
static func next_cost(id: String, level: int) -> int:
	var costs: Array = node(id).get("costs", [])
	return costs[level] if level < costs.size() else -1


static func boon(id: String) -> Dictionary:
	for b in BOONS:
		if b["id"] == id:
			return b
	return {}


## Turns Lamp Tree levels into the multipliers a night uses.
static func stats(levels: Dictionary) -> Dictionary:
	var lv := func(id: String) -> int: return int(levels.get(id, 0))
	return {
		"flame_mult": 1.0 + 0.25 * lv.call("thick_wick"),
		"radius_mult": 1.0 + 0.10 * lv.call("wide_glow"),
		"burn_mult": 1.0 + 0.20 * lv.call("hot_flame"),
		"tallow_mult": 1.0 + 0.30 * lv.call("rendering_vat"),
		"sconces": Tuning.START_SCONCES + lv.call("extra_sconce"),
		"foresight": Tuning.FORESIGHT_SECONDS + lv.call("foresight"),
		"afterglow": AFTERGLOW_SECONDS[clampi(lv.call("afterglow"), 0, 3)],
		"kindling": lv.call("kindling"),
	}
