extends SceneTree
## Picks a recorded match's best 15-25 s and writes the segments file the highlight render takes.
## env: PS_IN=/abs/match.psr  PS_SEGS=/abs/segs.json  [PS_MIN=15 PS_MAX=25]

func _initialize() -> void:
	var r := Replay.load_file(OS.get_environment("PS_IN"))
	if r == null:
		print("PICK failed: can't read ", OS.get_environment("PS_IN")); quit(1); return
	var hl := r.pick_highlight(float(OS.get_environment("PS_MIN")) if OS.has_environment("PS_MIN") else 15.0,
		float(OS.get_environment("PS_MAX")) if OS.has_environment("PS_MAX") else 25.0)
	var kinds := {}
	for e in r.events:
		if int(e.f) >= hl.x and int(e.f) <= hl.y and e.kind != "hit": kinds[e.kind] = int(kinds.get(e.kind, 0)) + 1
	var fa := FileAccess.open(OS.get_environment("PS_SEGS"), FileAccess.WRITE)
	fa.store_string(JSON.stringify([{"psr": OS.get_environment("PS_IN"), "from": hl.x, "to": hl.y}]))
	fa.close()
	print("PICK frames %d-%d (%.1f s) of %d: %s" % [hl.x, hl.y, (hl.y - hl.x) / 60.0, r.frames.size(), str(kinds)])
	quit()
