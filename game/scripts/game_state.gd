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
## Each Dawn pays one Daylight and the sun takes every Echo.
var daylight := 0
var dawns := 0
## When the first Dawn came: the run, and the minutes of night played before it.
var first_dawn_run := 0
var first_dawn_seconds := 0.0
## Seconds of night played across every run.
var night_seconds := 0.0
## Unix time of the last save. The Vigil pays Tallow for the time away since then.
var last_seen := 0.0
## What the Vigil paid on this launch, for the title screen to mention once.
var vigil_paid := 0
var vigil_away := 0.0

## Where progress is saved, and whether changes save themselves (tests turn it off).
var save_path := SaveGame.PATH
var autosave := true

## Each braid costs this much Tallow per run already in the Chorus.
const BRAID_COST := 40
const CHORUS_MAX := 3
## The Vigil: while the game is closed, kept Echoes keep watch and earn Tallow.
## Time away below the minimum pays nothing; time beyond the cap is not counted.
const VIGIL_MIN_AWAY := 600.0
const VIGIL_MAX_AWAY := 12.0 * 3600.0
## Tallow per hour away, per shadow the kept Echoes burned in their own runs.
const VIGIL_RATE := 0.02


func _ready() -> void:
	SaveGame.load_into(self, save_path)
	collect_vigil(Time.get_unix_time_from_system())


func save() -> void:
	if autosave:
		last_seen = Time.get_unix_time_from_system()
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
	daylight = 0
	dawns = 0
	first_dawn_run = 0
	first_dawn_seconds = 0.0
	night_seconds = 0.0
	last_seen = 0.0
	vigil_paid = 0
	vigil_away = 0.0


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
	if let_go.size() > SaveGame.LET_GO_KEPT:
		let_go.pop_front()
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


## Tallow earned from a night: shadows burned, weighted by kind. `seconds` is
## how long the night lasted, added to the total time played.
func award(burned_by_kind: Dictionary, seconds := 0.0) -> int:
	night_seconds += seconds
	var raw := 0.0
	for kind in burned_by_kind:
		raw += burned_by_kind[kind] * Tuning.TALLOW_PER_KIND.get(kind, 1.0)
		total_burned += burned_by_kind[kind]
	var earned := int(raw * stats()["tallow_mult"])
	tallow += earned
	return earned


# --- Dawn and the Vigil ------------------------------------------------------------

## The night is held until 6 AM: one Daylight, and the sun takes every Echo.
## Returns true for the first Dawn.
func greet_dawn(rec: EchoRecording) -> bool:
	best_time = maxf(best_time, rec.duration)
	dawns += 1
	daylight += 1
	if dawns == 1:
		first_dawn_run = rec.run_number
		first_dawn_seconds = night_seconds
	echoes.clear()
	return dawns == 1


## Tallow per hour the kept Echoes earn while the game is closed.
func vigil_rate() -> float:
	var burned := 0
	for rec in all_recordings():
		burned += rec.burned
	return burned * VIGIL_RATE * stats()["tallow_mult"]


## Pays the Vigil for the time since the last save. Returns the Tallow paid.
func collect_vigil(now: float) -> int:
	vigil_paid = 0
	vigil_away = 0.0
	if last_seen <= 0.0:
		return 0
	var away := now - last_seen
	if away < VIGIL_MIN_AWAY:
		return 0
	vigil_away = minf(away, VIGIL_MAX_AWAY)
	vigil_paid = int(vigil_rate() * vigil_away / 3600.0)
	tallow += vigil_paid
	# Count each stretch away once, even if the game closes before the next save.
	last_seen = now
	if vigil_paid > 0:
		save()
	return vigil_paid


# --- Braiding ---------------------------------------------------------------------

## The cost grows with the size of the Chorus the braid makes, whichever side
## is braided into which. Without `other`, the cost of braiding in a single run.
func braid_cost(into: EchoRecording, other: EchoRecording = null) -> int:
	var joining := 1 if other == null else other.members().size()
	return BRAID_COST * (into.members().size() + joining - 1)


func can_braid(into: EchoRecording, other: EchoRecording) -> bool:
	return into != other and echoes.has(into) and echoes.has(other) \
		and into.members().size() + other.members().size() <= CHORUS_MAX \
		and tallow >= braid_cost(into, other)


## Braids `other` (and anything braided into it) into `into`, freeing a Sconce.
func braid(into: EchoRecording, other: EchoRecording) -> bool:
	if not can_braid(into, other):
		return false
	tallow -= braid_cost(into, other)
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
		var bot := Bot.new("kite", run_number)
		while not sim.is_over():
			sim.step(1.0 / 30.0, bot.steer(sim))
			if sim.pending_level_ups > 0:
				sim.pick_boon(bot.pick_boon(sim))
		_add(sim.recording)
		run_number += 1
