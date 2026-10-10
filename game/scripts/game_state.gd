extends Node
## Autoload: everything that survives between runs. SaveGame writes it to disk.

## Kept Echoes, one per Sconce. A Chorus keeps its braided runs in `chorus`.
var echoes: Array[EchoRecording] = []
var run_number := 1
## Echoes the player let go. The night keeps them.
var let_go: Array[EchoRecording] = []
var let_go_count := 0
var best_time := 0.0
var tallow := 0
var total_burned := 0
## Lamp Tree levels by node id.
var tree_levels := {}

## Where progress is saved, and whether changes save themselves (tests turn it off).
var save_path := SaveGame.PATH
var autosave := true

## Each braid costs this much Tallow per run already in the Chorus.
const BRAID_COST := 40
const CHORUS_MAX := 3


func _ready() -> void:
	SaveGame.load_into(self, save_path)


func save() -> void:
	if autosave:
		SaveGame.save(self, save_path)


func reset() -> void:
	echoes.clear()
	let_go.clear()
	let_go_count = 0
	run_number = 1
	best_time = 0.0
	tallow = 0
	total_burned = 0
	tree_levels = {}


func stats() -> Dictionary:
	return Upgrades.stats(tree_levels)


var sconces: int:
	get:
		return stats()["sconces"]


## Every run that walks tonight: kept Echoes and the runs braided into them.
func all_recordings() -> Array[EchoRecording]:
	var out: Array[EchoRecording] = []
	for e in echoes:
		for m in e.members():
			m.hue_index = e.hue_index
			out.append(m)
	return out


func needs_choice() -> bool:
	return echoes.size() >= sconces


## Keeps a finished run as an Echo when there is a free Sconce. Returns false when full.
func try_keep(rec: EchoRecording) -> bool:
	best_time = maxf(best_time, rec.duration)
	if needs_choice():
		return false
	_add(rec)
	return true


## Resolves a full Sconce: `new_rec` is kept unless it is the one let go.
func let_go_of(chosen: EchoRecording, new_rec: EchoRecording) -> void:
	let_go.append(chosen)
	let_go_count += 1
	if chosen != new_rec:
		echoes.erase(chosen)
		_add(new_rec)


## Adds an Echo with the first color no other kept Echo is using.
func _add(rec: EchoRecording) -> void:
	var used := echoes.map(func(e): return e.hue_index)
	rec.hue_index = 0
	while used.has(rec.hue_index) and rec.hue_index < EchoRecording.HUES.size() - 1:
		rec.hue_index += 1
	echoes.append(rec)


func begin_next_run() -> void:
	run_number += 1


# --- Tallow and the Lamp Tree ---------------------------------------------------

func level(id: String) -> int:
	return int(tree_levels.get(id, 0))


func can_buy(id: String) -> bool:
	var cost := Upgrades.next_cost(id, level(id))
	return cost >= 0 and tallow >= cost


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	tallow -= Upgrades.next_cost(id, level(id))
	tree_levels[id] = level(id) + 1
	return true


## Tallow earned from a night: shadows burned, weighted by kind.
func award(burned_by_kind: Dictionary) -> int:
	var raw := 0.0
	for kind in burned_by_kind:
		raw += burned_by_kind[kind] * Tuning.TALLOW_PER_KIND.get(kind, 1.0)
		total_burned += burned_by_kind[kind]
	var earned := int(raw * stats()["tallow_mult"])
	tallow += earned
	return earned


# --- Braiding ---------------------------------------------------------------------

func braid_cost(into: EchoRecording) -> int:
	return BRAID_COST * into.members().size()


func can_braid(into: EchoRecording, other: EchoRecording) -> bool:
	return into != other and echoes.has(into) and echoes.has(other) \
		and into.members().size() + other.members().size() <= CHORUS_MAX \
		and tallow >= braid_cost(into)


## Braids `other` (and anything braided into it) into `into`, freeing a Sconce.
func braid(into: EchoRecording, other: EchoRecording) -> bool:
	if not can_braid(into, other):
		return false
	tallow -= braid_cost(into)
	into.chorus.append_array(other.members())
	other.chorus.clear()
	echoes.erase(other)
	return true


## Dev helper for screenshots and footage: fills the Sconces with bot-played runs.
func make_demo_echoes(count: int) -> void:
	reset()
	tree_levels["extra_sconce"] = clampi(count - Tuning.START_SCONCES, 0, Upgrades.max_level("extra_sconce"))
	for i in count:
		var sim := NightSim.new(all_recordings(), Tuning.NIGHT_SEED, run_number, stats())
		var bot := Bot.new("kite")
		while not sim.is_over():
			sim.step(1.0 / 30.0, bot.steer(sim))
			if sim.pending_level_ups > 0:
				sim.pick_boon(bot.pick_boon(sim))
		_add(sim.recording)
		run_number += 1
