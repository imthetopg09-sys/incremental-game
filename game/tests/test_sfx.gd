extends RefCounted
## Procedural sound: safe to spam, a fixed pool of players, a pad under heavy burns.


func _sfx(t) -> Node:
	var sfx = t.root.get_node_or_null("Sfx")
	t.check(sfx != null, "Sfx autoload is present")
	if sfx != null:
		sfx.stop_all()
		sfx.volume = 0.8
	return sfx


func _player_count(sfx: Node) -> int:
	return sfx.get_children().filter(func(c): return c is AudioStreamPlayer).size()


func test_every_sound_can_be_spammed(t) -> void:
	var sfx = _sfx(t)
	if sfx == null:
		return
	var players := _player_count(sfx)
	var most := 0
	for i in 300:
		sfx.burn(i % 7 - 1, i % 11 == 0)
		sfx.level_up()
		sfx.strike()
		sfx.death()
		sfx.dawn()
		sfx.ui_click()
		most = maxi(most, sfx.active_players)
		if i % 25 == 0:
			await t.process_frame
	t.check(most > 0, "spamming played something")
	t.check(most <= sfx.POOL_SIZE, "%d one-shots at once, pool is %d" % [most, sfx.POOL_SIZE])
	t.check(_player_count(sfx) == players, "no players were added while spamming")
	sfx.stop_all()
	t.check(sfx.active_players == 0 and sfx.pad_level == 0.0, "stop_all silences everything")


func test_burns_stay_in_the_pool(t) -> void:
	var sfx = _sfx(t)
	if sfx == null:
		return
	var most := 0
	# Every voice at once, frame after frame, with an occasional bloat.
	for frame in 40:
		for v in range(-1, 5):
			sfx.burn(v, frame % 9 == 0)
			most = maxi(most, sfx.active_players)
		await t.process_frame
	t.check(most <= sfx.POOL_SIZE, "%d one-shots at once, pool is %d" % [most, sfx.POOL_SIZE])
	# A chime still gets through a pool full of burns.
	var before: int = sfx.active_players
	sfx.level_up()
	t.check(sfx.active_players >= mini(before + 1, sfx.POOL_SIZE), "level_up found a player")
	sfx.stop_all()


func test_trickle_plays_notes_and_rush_swells_the_pad(t) -> void:
	var sfx = _sfx(t)
	if sfx == null:
		return
	# A slow trickle: single notes, no pad.
	for i in 5:
		sfx.burn(-1)
		await t.create_timer(0.12).timeout
	t.check(sfx.active_players > 0, "a trickle of burns plays notes")
	t.check(sfx.pad_level == 0.0, "no pad for a trickle, pad is %.3f" % sfx.pad_level)
	t.check(sfx.burn_rate < sfx.PAD_ON_RATE, "trickle rate %.1f is under the pad threshold" % sfx.burn_rate)
	# A rush: far more than 20 burns a second.
	for frame in 20:
		for k in 6:
			sfx.burn(k % 5)
		await t.process_frame
	t.check(sfx.burn_rate >= sfx.PAD_ON_RATE, "rush rate %.1f is over the pad threshold" % sfx.burn_rate)
	t.check(sfx.pad_level > 0.0, "a rush of burns swells the pad")
	# While the pad is up, ordinary burns add no single notes.
	var before: int = sfx.active_players
	for k in 30:
		sfx.burn(k % 5)
	t.check(sfx.active_players <= before, "pad mode adds no notes (%d -> %d)" % [before, sfx.active_players])
	# When the rush stops the burn rate falls and the pad fades.
	var peak: float = sfx.pad_level
	var faded := false
	for i in 50:
		await t.create_timer(0.1).timeout
		peak = maxf(peak, sfx.pad_level)
		if sfx.burn_rate < sfx.PAD_OFF_RATE and sfx.pad_level < peak * 0.8:
			faded = true
			break
	t.check(faded, "the pad fades after the rush (peak %.3f, now %.3f)" % [peak, sfx.pad_level])
	sfx.stop_all()


func test_volume_is_clamped_and_silences(t) -> void:
	var sfx = _sfx(t)
	if sfx == null:
		return
	sfx.volume = 3.0
	t.check(is_equal_approx(sfx.volume, 1.0), "volume clamps to 1, got %.2f" % sfx.volume)
	sfx.volume = -1.0
	t.check(sfx.volume == 0.0, "volume clamps to 0, got %.2f" % sfx.volume)
	sfx.burn(-1)
	sfx.level_up()
	sfx.ui_click()
	t.check(sfx.active_players == 0, "nothing plays at volume 0")
	sfx.volume = 0.8
	sfx.ui_click()
	t.check(sfx.active_players == 1, "a click plays at volume 0.8")
	sfx.stop_all()
