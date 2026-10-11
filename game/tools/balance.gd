extends SceneTree
## Headless balance report: plays many nights with bots the way a player would.
## The bot drafts Boons on level-ups, keeps its longest runs as Echoes, earns Tallow
## and buys Lamp Tree upgrades between nights. Prints how far each night got.
## Usage: godot --headless --path game -s res://tools/balance.gd -- [runs] [style] [no-shop] [seed=N] [hz=N]
## Styles: still, flee, kite, shield. seed changes where shadows come from (the game
## always uses Tuning.NIGHT_SEED); hz is the step rate (the game steps at 60).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 15
	var style: String = args[1] if args.size() > 1 else "kite"
	var shop := not args.has("no-shop")
	var seed_value := Tuning.NIGHT_SEED
	var hz := 30.0
	for a in args:
		if a.begins_with("seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a.begins_with("hz="):
			hz = float(a.get_slice("=", 1))
	var dt := 1.0 / hz
	var gs = load("res://scripts/game_state.gd").new()
	var minutes := 0.0
	var first_dawn := -1
	var first_dawn_minutes := 0.0
	var durations := []
	for run in range(1, runs + 1):
		var sim := NightSim.new(gs.all_recordings(), seed_value, run, gs.stats())
		var bot := Bot.new(style, run)
		while not sim.is_over():
			if sim.pending_level_ups > 0:
				sim.pick_boon(bot.pick_boon(sim))
			sim.step(dt, bot.steer(sim))
		var rec := sim.recording
		minutes += rec.duration / 60.0 + 0.5  # plus time on the end and tree screens
		durations.append(int(rec.duration))
		var earned: int = gs.award(sim.burned_by_kind, rec.duration)
		if not rec.died:
			# Dawn: the sun takes every Echo, as in the game.
			gs.greet_dawn(rec)
		elif not gs.try_keep(rec):
			# Let go of the shortest run, which may be this one.
			var worst := rec
			for e in gs.echoes:
				if e.duration < worst.duration:
					worst = e
			gs.let_go_of(worst, rec)
		if shop:
			Bot.shop(gs)
		if not rec.died and first_dawn < 0:
			first_dawn = run
			first_dawn_minutes = minutes
		print("run %2d  %-6s %s  lvl %2d  burned %4d (echoes %4d)  +%4d tallow  tree %s  %4.1f min" % [
			run, style, NightClock.label(rec.duration) if rec.died else "DAWN    ", sim.level,
			sim.burned, sim.burned_by_echoes, earned, _tree(gs), minutes])
	print("first dawn: %s" % (("run %d at %.1f min" % [first_dawn, first_dawn_minutes]) if first_dawn > 0 else "not reached"))
	print("summary %s%s seed %d: dawn %s  seconds %s" % [style, "" if shop else "/no-shop", seed_value,
		str(first_dawn) if first_dawn > 0 else "-", " ".join(durations.map(func(d): return str(d)))])
	gs.free()
	quit()


func _tree(gs) -> String:
	var parts := []
	for n in Upgrades.TREE:
		parts.append(str(gs.level(n["id"])))
	return "".join(parts)
