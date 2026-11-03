extends SceneTree
## Media montage for the owner from two recordings: A = a 1v1 with cinematics (Power Change, fusion, KO), B = a 4-fighter
## Battle Royale. env: PS_A, PS_B (abs .psr), PS_SEGS (abs out .json), PS_TITLE, [PS_C: another match, used for the
## fusion when A and B have none].
## Order: B wide opening (title card) > A Power Change cutscene > A fusion > B brawl (busiest 8 s) > A final KO.

func _first(r: Replay, kind: String, after := 0) -> int:
	for e in r.events:
		if e.kind == kind and int(e.f) >= after: return int(e.f)
	return -1

func _last(r: Replay, kind: String) -> int:
	var f := -1
	for e in r.events: if e.kind == kind: f = int(e.f)
	return f

func _initialize() -> void:
	var a := Replay.load_file(OS.get_environment("PS_A")); var b := Replay.load_file(OS.get_environment("PS_B"))
	var pa := OS.get_environment("PS_A"); var pb := OS.get_environment("PS_B")
	var segs := []
	var na := a.frames.size() - 1; var nb := b.frames.size() - 1
	# busiest 8 s of B (most hits), after its first 3 s
	var best := 180; var bs := -1e9
	for s0 in range(180, maxi(181, nb - 480), 30):
		var c := 0.0
		for e in b.events: if int(e.f) >= s0 and int(e.f) < s0 + 480 and e.kind in ["hit", "down", "power", "fusion"]: c += 1.0
		var spread := 0.0; var ns := 0
		for k in range(s0, mini(nb, s0 + 480), 40):   # all four close together reads better than a wide shot
			var fs: Array = (b.frames[k] as Dictionary).f
			var mx := 0.0
			for i in fs.size():
				for j in range(i + 1, fs.size()):
					mx = maxf(mx, Vector2(fs[i][0] - fs[j][0], fs[i][2] - fs[j][2]).length())
			spread += mx; ns += 1
		c -= 0.6 * spread / maxf(1, ns)
		if c > bs: bs = c; best = s0
	segs.append({"psr": pb, "from": 100, "to": 280, "title": OS.get_environment("PS_TITLE") if OS.has_environment("PS_TITLE") else ""})
	var p := _first(a, "power")
	if p >= 0: segs.append({"psr": pa, "from": maxi(0, p - 80), "to": mini(na, p + 150)})
	var fu := _first(a, "fusion")
	var src := a; var sp := pa
	if fu < 0: fu = _first(b, "fusion"); src = b; sp = pb
	if fu < 0 and OS.has_environment("PS_C"):   # a third recording just for a Power Fusion
		var c := Replay.load_file(OS.get_environment("PS_C"))
		if c: src = c; sp = OS.get_environment("PS_C"); fu = _first(c, "fusion")
	if fu >= 0: segs.append({"psr": sp, "from": maxi(0, fu - 25), "to": mini(src.frames.size() - 1, fu + 125)})
	segs.append({"psr": pb, "from": best, "to": mini(nb, best + 480)})
	var k := _last(a, "ko")
	if k >= 0: segs.append({"psr": pa, "from": maxi(0, k - 150), "to": mini(na, k + 216)})
	var tot := 0
	for s in segs: tot += int(s.to) - int(s.from) + 1
	var fa := FileAccess.open(OS.get_environment("PS_SEGS"), FileAccess.WRITE); fa.store_string(JSON.stringify(segs)); fa.close()
	print("MONTAGE %d segments, %.1f s: %s" % [segs.size(), tot / 60.0, str(segs.map(func(s): return [s.psr.get_file(), s.from, s.to]))])
	quit()
