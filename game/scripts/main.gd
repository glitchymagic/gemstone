extends Node
## Entry scene: hands over to the title screen.
## Command line (after --): --highlight <segments.json> [--quality N] renders a highlight in the replay theater
## (used with --write-movie; see Highlight).

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var hi := a.find("--highlight")
	if hi >= 0 and hi + 1 < a.size():
		var segs = JSON.parse_string(FileAccess.get_file_as_string(a[hi + 1]))
		if segs is Array and not segs.is_empty():
			var qi := a.find("--quality")
			Game.quality = int(a[qi + 1]) if qi >= 0 and qi + 1 < a.size() else 3
			var t := ReplayTheater.new()
			t.render = true; t.segments = segs
			Game.cinematics = true
			Game._set_screen(t)
			return
	Game.goto_title()
