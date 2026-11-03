extends RefCounted
## Training room, headless (after the attract tests in run_tests.gd): Falcon jabs a standing Ryoma dummy; the overlay's
## attack spheres are live exactly on the frames the game's hit steps say, the frame-data panel reports that window,
## the hit lands with the game's damage, health refills, a KO doesn't end the round, the clock stands still, the
## jumping dummy jumps.

var t: SceneTree
var fight: Fight
var n := 0
var finished := false
var live: Array = []
var key := ""
var drawn := false
var hits := 0
var y0 := 0.0
var y_max := -100.0

func _init(runner: SceneTree) -> void:
	t = runner

func check(c: bool, what: String) -> void:
	t.call("check", c, what)

func _jab() -> void:
	var p: Fighter = fight.fighters[0]; var d: Fighter = fight.fighters[1]
	var dir := p.global_position - d.global_position; dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	p.global_position = d.global_position + dir * 0.9
	p.velocity = Vector3.ZERO
	p.set_state(Fighter.S.IDLE)
	p._start_attack("punch1")
	p.set_state(Fighter.S.ATTACK)

func tick() -> void:
	n += 1
	if n == 1:
		print("== training room")
		fight = Fight.new(); fight.test_mode = true; fight.training = true
		fight.chars = ["falcon", "ryoma"]; fight.cpu_flags = [false, true]
		t.root.add_child(fight)
		fight.fighters[1].damaged.connect(func(_v, _d): hits += 1)
		return
	var p: Fighter = fight.fighters[0]; var d: Fighter = fight.fighters[1]
	var tr: Training = fight.trainer
	if n == 2:
		check(tr != null and tr.dummy == "stand" and not tr.uses_cpu(), "training: a standing dummy, no CPU")
	if n == 40: _jab()
	if n > 40 and n <= 90:
		var sp := Training.attack_spheres(p)
		if not sp.is_empty():
			var mo := p._motion()
			live.append(int(mo[1])); key = String(mo[0])
			if tr.mesh.get_surface_count() > 0: drawn = true
	if n == 91:
		check(live.size() >= 2, "jab: attack spheres live on frames %s (%s)" % [str(live), key])
		var fd := Training.frame_data(p, key)
		var lo: int = live.min() if live.size() > 0 else -9
		var hi: int = live.max() if live.size() > 0 else -9
		check(fd.live == Vector2i(lo, hi), "frame data = the frames the spheres were live (%s vs %d-%d)" % [str(fd.live), lo, hi])
		check(fd.live == Vector2i(5, 8), "Falcon's jab live on frames 5-8 (the game's logged window)")
		check(fd.total > fd.live.y and fd.recovery > 0 and fd.dmg > 0, "frame data: total %d, recovery %d, base damage %d" % [fd.total, fd.recovery, fd.dmg])
		check(drawn, "overlay draws the live attack spheres")
		check(hits >= 1 and int(tr.last.dmg) > 0, "the jab lands on the dummy (%d damage)" % int(tr.last.dmg))
	if n == 200:
		check(d.hp == Rules.MAX_HP, "health refills after the hit")
		check(is_equal_approx(fight.timer, Rules.ROUND_TIME), "the clock stands still")
		tr.refill = false
		d.hp = 1
		_jab()
	if n == 320:
		check(fight.phase == Fight.R.FIGHT and d.hp == Rules.MAX_HP, "a KO in training: back up with full health, the round goes on")
		tr.dummy = "jump"
		y0 = d.global_position.y
	if n > 320 and n < 440:
		y_max = maxf(y_max, d.global_position.y)
	if n == 440:
		check(y_max > y0 + 0.4, "dummy on JUMP jumps (%.2f m)" % (y_max - y0))
		fight.queue_free()
		finished = true
