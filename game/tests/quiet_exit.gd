## BUG-38 (fx-cov2): "N ObjectDB instances were leaked at exit" + "N resources still in use at exit" after headless
## --fixed-fps runs were the sound effects' AudioStreamPlaybackWAVs: the frames run faster than the audio thread, which is
## the only one that frees a stopped / finished playback, so quit() came before it caught up. A real-time run (the game
## itself) never shows it. Stop every player, give the audio thread a moment, then quit (tests/_leak_probe in the
## fx-cov2 notes: 17 leaked -> 0 with the wait).
static func drain(root: Node) -> void:
	for t in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		for ap in root.find_children("*", t, true, false): ap.call("stop")
	OS.delay_msec(250)
