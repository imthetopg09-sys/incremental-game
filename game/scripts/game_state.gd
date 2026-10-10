extends Node
## Autoload: everything that survives between runs. Saving arrives in step 3.

var echoes: Array[EchoRecording] = []
var sconces := Tuning.START_SCONCES
var run_number := 1
## Echoes the player let go. The night keeps them.
var let_go: Array[EchoRecording] = []
var best_time := 0.0


func reset() -> void:
	echoes.clear()
	let_go.clear()
	sconces = Tuning.START_SCONCES
	run_number = 1
	best_time = 0.0


func needs_choice() -> bool:
	return echoes.size() >= sconces


## Keeps a finished run as an Echo when there is a free Sconce. Returns false when full.
func try_keep(rec: EchoRecording) -> bool:
	best_time = maxf(best_time, rec.duration)
	if needs_choice():
		return false
	echoes.append(rec)
	return true


## Resolves a full Sconce: `new_rec` is kept unless it is the one let go.
func let_go_of(chosen: EchoRecording, new_rec: EchoRecording) -> void:
	let_go.append(chosen)
	if chosen != new_rec:
		echoes.erase(chosen)
		echoes.append(new_rec)


func begin_next_run() -> void:
	run_number += 1


## Dev helper for screenshots and footage: fills the Sconces with bot-played runs.
func make_demo_echoes(count: int) -> void:
	reset()
	sconces = maxi(sconces, count)
	for i in count:
		var sim := NightSim.new(echoes.duplicate(), Tuning.NIGHT_SEED, run_number)
		var bot := Bot.new("kite")
		while not sim.is_over():
			sim.step(1.0 / 30.0, bot.steer(sim))
		echoes.append(sim.recording)
		run_number += 1
