extends SceneTree
## Headless balance report: plays many nights with bots, keeping Echoes the way a
## player would (drop the shortest run), and prints how long each run survives.
## Usage: godot --headless --path game -s res://tools/balance.gd -- [runs] [style]

const DT := 1.0 / 30.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 12
	var style: String = args[1] if args.size() > 1 else "kite"
	var echoes: Array[EchoRecording] = []
	var line := ""
	for run in range(1, runs + 1):
		var sim := NightSim.new(echoes.duplicate(), Tuning.NIGHT_SEED, run)
		var bot := Bot.new(style)
		while not sim.is_over():
			sim.step(DT, bot.steer(sim))
		var rec := sim.recording
		echoes.append(rec)
		if echoes.size() > Tuning.START_SCONCES:
			echoes.sort_custom(func(a, b): return a.duration > b.duration)
			echoes.resize(Tuning.START_SCONCES)
		print("run %2d  %-6s  %s  burned %3d (echoes %3d)  shadows alive %3d" % [
			run, style, NightClock.label(rec.duration) if rec.died else "DAWN    ",
			sim.burned, sim.burned_by_echoes, sim.shadows.size()])
	quit()
