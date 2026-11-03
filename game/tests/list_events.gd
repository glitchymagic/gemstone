extends SceneTree
## Prints the marked moments of recorded matches. env: PS_IN=/abs/a.psr[,/abs/b.psr]
func _initialize() -> void:
	for p in OS.get_environment("PS_IN").split(","):
		var r := Replay.load_file(p)
		var k := {}
		for e in r.events: k[e.kind] = int(k.get(e.kind, 0)) + 1
		var fus := r.events.filter(func(e): return e.kind == "fusion").map(func(e): return int(e.f))
		print("EVENTS %s %d frames %s fusion@%s" % [p.get_file(), r.frames.size(), str(k), str(fus)])
	quit()
