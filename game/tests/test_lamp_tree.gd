extends RefCounted
## The Lamp Tree screen: buying nodes and braiding Echoes through its handlers.

const SCENE := "res://scenes/lamp_tree.tscn"


func _rec(run: int) -> EchoRecording:
	var r := EchoRecording.new()
	r.run_number = run
	for i in 30:
		r.record_until(i / EchoRecording.RATE, Vector2(200 + i * 10, 200 + run * 40))
	r.finish(29 / EchoRecording.RATE, Vector2(490, 200 + run * 40), true)
	return r


func _boot(t) -> Node:
	var tree := (load(SCENE) as PackedScene).instantiate()
	t.root.add_child(tree)
	tree.input_delay = 0.0
	for i in 3:
		await t.process_frame
	return tree


## Frees the scene, silences its chimes and resets the autoload for the next test.
func _done(t, tree: Node) -> void:
	tree.free()
	var sfx = t.root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.stop_all()
	t.root.get_node("GameState").reset()


func _click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


func test_buying_spends_tallow_and_levels_up(t) -> void:
	var gs = t.root.get_node("GameState")
	gs.reset()
	var cost := Upgrades.next_cost("thick_wick", 0)
	gs.tallow = cost + 5
	var tree = await _boot(t)
	t.check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the cursor shows")
	t.check(tree.tallow_label.text == "%d Tallow" % (cost + 5), "header shows the Tallow, got %s" % tree.tallow_label.text)
	t.check(tree.grid.get_child_count() == Upgrades.TREE.size(), "one card per tree node")
	t.check(tree.try_buy("thick_wick"), "an affordable buy succeeds")
	t.check(gs.level("thick_wick") == 1, "level is 1, got %d" % gs.level("thick_wick"))
	t.check(gs.tallow == 5, "cost was paid, %d left" % gs.tallow)
	t.check(tree.tallow_label.text == "5 Tallow", "header refreshed, got %s" % tree.tallow_label.text)
	t.check(not tree.try_buy("thick_wick"), "a buy that costs too much fails")
	t.check(gs.level("thick_wick") == 1 and gs.tallow == 5, "a failed buy changes nothing")

	# Clicking a card buys it too.
	gs.tallow = Upgrades.next_cost("wide_glow", 0)
	tree._cards["wide_glow"]["panel"].gui_input.emit(_click())
	t.check(gs.level("wide_glow") == 1 and gs.tallow == 0, "a click on the card bought Wide Glow")

	gs.tallow = 100000
	for i in Upgrades.max_level("foresight"):
		tree.try_buy("foresight")
	t.check(gs.level("foresight") == Upgrades.max_level("foresight"), "Foresight maxed")
	var left: int = gs.tallow
	t.check(not tree.try_buy("foresight"), "a maxed node cannot be bought")
	t.check(gs.tallow == left, "nothing spent on a maxed node")
	t.check(tree._cards["foresight"]["cost"].text == "Max", "maxed card reads Max")
	_done(t, tree)


func test_sconce_slots_follow_the_echoes(t) -> void:
	var gs = t.root.get_node("GameState")
	gs.reset()
	gs.try_keep(_rec(1))
	var tree = await _boot(t)
	var most := Tuning.START_SCONCES + Upgrades.max_level("extra_sconce")
	t.check(tree.slots_box.get_child_count() == most, "%d slots, got %d" % [most, tree.slots_box.get_child_count()])
	t.check(tree._slots[0]["rec"] == gs.echoes[0], "the kept Echo is in the first slot")
	t.check(tree._slots[1]["rec"] == null and not tree._slots[1]["locked"], "a free Sconce is hollow")
	t.check(tree._slots[most - 1]["locked"], "Sconces the tree can still grow are locked")
	t.check(tree.sconce_count.text == "1 of %d filled" % gs.sconces, "count reads %s" % tree.sconce_count.text)
	_done(t, tree)


func test_braiding_by_clicking_two_echoes(t) -> void:
	var gs = t.root.get_node("GameState")
	gs.reset()
	var a := _rec(1)
	var b := _rec(2)
	var c := _rec(3)
	for r in [a, b, c]:
		gs.try_keep(r)
	gs.tallow = gs.braid_cost(a)
	var tree = await _boot(t)

	t.check(not tree.click_echo(a), "the first click only picks")
	t.check(tree.selected == a, "Run 1 is picked")
	t.check(str(gs.braid_cost(a)) in tree.braid_hint.text, "hint shows the cost: %s" % tree.braid_hint.text)
	tree.click_echo(a)
	t.check(tree.selected == null, "clicking the same Echo again deselects")

	tree.click_echo(a)
	t.check(tree.click_echo(b), "the second click braids")
	t.check(gs.echoes.size() == 2 and not gs.echoes.has(b), "Run 2 left its Sconce")
	t.check(a.members().size() == 2 and a.chorus.has(b), "Run 2 walks in Run 1's Chorus")
	t.check(gs.tallow == 0, "braid was paid for, %d left" % gs.tallow)
	t.check(tree.selected == null, "nothing picked after a braid")
	t.check(tree._slots[0]["rec"] == a and tree._slots[0]["extra"].text == "Chorus of 2 runs", "slot shows the Chorus")
	t.check(tree._slots[2]["rec"] == null and not tree._slots[2]["locked"], "a Sconce came free")

	# Too dear: the pick stays and nothing changes.
	tree.click_echo(a)
	t.check(not tree.click_echo(c), "a braid that costs too much fails")
	t.check(gs.echoes.size() == 2 and a.members().size() == 2, "nothing braided")
	t.check(tree.selected == a, "the pick survives a failed braid")

	# Esc drops the pick before it leaves for the title.
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	tree._unhandled_input(esc)
	t.check(tree.selected == null, "Esc deselects")
	t.check(not tree._leaving, "and stays on the Lamp Tree")
	_done(t, tree)
