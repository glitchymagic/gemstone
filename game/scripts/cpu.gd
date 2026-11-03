class_name CPU
extends RefCounted
## CPU player: approaches, strings punches/kicks, grabs and throws, chases gems, picks up and
## throws objects, uses poles, wall-jumps out of corners, uses Power Drive / Fusion when changed.

var me: Fighter
var arena: Arena
var input := PInput.new()
var rng := RandomNumberGenerator.new()
var think_t := 0.0
var goal := "fight"
var press := {}
var level := 0.75   # 0..1 aggression/accuracy

var fv: CPUFV = null   # Final Valgas: his own AI from the disc (cpu_fv.gd, 0x0C08D5CE) drives him, not _boss_tick

func _init(p_me: Fighter, p_arena: Arena, seed_val := 7) -> void:
	me = p_me; arena = p_arena; rng.seed = seed_val
	if me.boss and not OS.has_environment("PS_FV_OLD") and CPUFV.load_data():
		fv = CPUFV.new(me, arena); fv.input = input

## Final Valgas's attack mix and idle gaps, from his logged CPU fight (fightlog.py show fv_cpu2 2): 99>100 x9,
## 99>100>101 x2, 99>100>103 x1, k1/2, k1/3, 4>16 once each; 16-105 frames idle between attacks
const BOSS_MOVES := [["drive_p", 9], ["drive_k", 2], ["fusion1", 1], ["punch1", 1], ["kick1", 1], ["fusion2", 1]]
var boss_gap := 0.7

func _boss_tick(dt: float) -> void:
	var now := {}
	for b in PInput.BUTTONS: now[b] = false
	input.set_state(Vector2.ZERO, now)
	if me.state != Fighter.S.IDLE or me.opponent == null: return
	boss_gap -= dt
	if boss_gap > 0.0: return
	boss_gap = rng.randf_range(16.0, 105.0) / 60.0
	var tot := 0
	for m in BOSS_MOVES: tot += int(m[1])
	var r := rng.randi_range(1, tot)
	for m in BOSS_MOVES:
		r -= int(m[1])
		if r <= 0:
			me.boss_attack(m[0]); return

## Battle Royale: who to go after. Each CPU leans one way (nearest / weakest / the one holding stones) and everyone
## hunts a fighter one stone away from a Power Change.
var style := ""
var unreachable := {}
var chase_t := 0.0
var chase_d := 99.0
func _pick_target() -> void:
	if style == "": style = ["nearest", "weakest", "gems"][rng.randi() % 3]
	var best: Fighter = null; var bs := -1e9
	for o in me.enemies:
		if unreachable.get(o, 0.0) > 0.0 and me.enemies.size() > 1: continue
		var d: float = (o.global_position - me.global_position).length()
		var sc := -d
		match style:
			"weakest": sc = -float(o.hp) / 100.0 - d * 0.3
			"gems": sc = float(o.gems) * 4.0 - d * 0.3
		if o.gems >= 2: sc += 3.0
		if o == me.opponent: sc += 0.8   # don't flip-flop
		if sc > bs: bs = sc; best = o
	if best: me.opponent = best

func tick(dt: float, cam_basis: Basis) -> void:
	if me.boss:
		if fv: fv.tick(dt, cam_basis)
		else: _boss_tick(dt)
		return
	if arena.fighters.size() > 2:
		for k in unreachable.keys(): unreachable[k] -= dt
		if goal == "fight" and me.opponent:   # no way to him (another level): someone else for 6 s
			var dd: float = (me.opponent.global_position - me.global_position).length()
			if dd > 2.5 and dd > chase_d - 0.2: chase_t += dt
			else: chase_t = 0.0; chase_d = dd
			if chase_t > 2.5: unreachable[me.opponent] = 6.0; chase_t = 0.0; chase_d = 99.0; think_t = 0.0
		if think_t <= 0.0 or me.opponent == null or me.opponent.hp <= 0: _pick_target()
	think_t -= dt
	var now := {}
	for b in PInput.BUTTONS: now[b] = false
	var opp := me.opponent
	var target := me.global_position
	if think_t <= 0.0:
		think_t = rng.randf_range(0.08, 0.22)
		_choose_goal()
	var dist := 99.0
	var dy := 0.0   # the opponent's height over me (stairs, ledges, tables)
	if opp:
		dist = Vector2(opp.global_position.x - me.global_position.x, opp.global_position.z - me.global_position.z).length()
		if opp.is_on_floor() and me.is_on_floor(): dy = opp.global_position.y - me.global_position.y
	match goal:
		"gem":
			var g := _nearest_gem()
			if g: target = g.global_position
			else: goal = "fight"
		"prop":
			var p := arena.nearest_prop(me.global_position, 30.0)
			if p and me.state != Fighter.S.CARRY:
				target = p.global_position
				if me.global_position.distance_to(p.global_position) < 1.2 and think_t < 0.1: now.action = true
			elif me.state == Fighter.S.CARRY and opp:
				target = opp.global_position
				if dist < 7.0 and think_t < 0.12: now.punch = true
			else: goal = "fight"
		"pole":   # the demo CPUs run at a pole and jump into it (the catch needs a moving jump)
			pole_t += dt
			var pl = _nearest_pole()
			if pl == null or me.state == Fighter.S.POLE: goal = "fight"
			else:
				target = pl
				var dp := Vector2(pl.x - me.global_position.x, pl.z - me.global_position.z).length()
				if dp < 2.2 and me.is_on_floor() and me.state in [Fighter.S.IDLE, Fighter.S.RUN]: now.jump = true
				if dp > 14.0: goal = "fight"
		"fight", "retreat":
			if opp: target = opp.global_position
			if goal == "retreat" and opp: target = arena.clamp_point(me.global_position + (me.global_position - opp.global_position), 0.6)
	var to := target - me.global_position; to.y = 0
	# unreachable goals (a gem on a ledge, a pole behind a rail): no progress for 1.5 s -> fight for 5 s
	avoid_t -= dt
	if goal != "fight":
		if to.length() < last_d - 0.3: last_d = to.length(); stuck_t = 0.0
		else: stuck_t += dt
		if stuck_t > 1.5: goal = "fight"; avoid_t = 5.0
	if goal == "fight": last_d = 99.0; stuck_t = 0.0
	var mv := Vector3.ZERO
	var stop := 0.95 if goal == "fight" else 0.3
	if goal == "fight" and dy < -0.9: stop = 0.0   # he's below me (stairs): go down to him, don't swing at his head
	if to.length() > stop: mv = to.normalized()
	elif goal == "fight" and dy < -0.9 and opp: mv = (opp.global_position - me.global_position).slide(Vector3.UP).normalized()
	if me.state == Fighter.S.CARRY and goal == "prop" and dist < 7.0: mv = Vector3.ZERO
	# any goal, fighting too: running with no progress for 1.5 s (a block, a step, a rail in the way) -> jump and
	# sidestep for 0.7 s (remaster AI; the stages with the game's throwable blocks stalled whole matches without it)
	if to.length() > 2.0 and me.state == Fighter.S.RUN and unstick_t <= 0.0:
		if to.length() < run_best - 0.3: run_best = to.length(); run_stuck = 0.0
		else: run_stuck += dt
		if run_stuck > 1.5:
			unstick_t = 0.7; run_stuck = 0.0; run_best = 99.0
			side = 1.0 if rng.randf() < 0.5 else -1.0
			if me.is_on_floor(): now.jump = true
	elif me.state != Fighter.S.RUN:
		run_best = 99.0; run_stuck = 0.0
	if unstick_t > 0.0 and to.length() > 0.1:
		unstick_t -= dt
		var t := to.normalized()
		mv = (t.cross(Vector3.UP) * side + t * 0.25).normalized()
	# a fighter a storey up or down is out of reach (the 2026-10-23 match video: 10 s of punching the air on Londo's
	# stairs): the lower one jumps at him, the upper one comes down, nobody throws ground attacks
	if goal == "fight" and opp and dy > 0.9 and dist < 3.0 and me.is_on_floor() and me.state in [Fighter.S.IDLE, Fighter.S.RUN] and rng.randf() < 0.12:
		now.jump = true
	if goal == "fight" and opp and dist < 1.6 and absf(dy) < 0.9 and me.state in [Fighter.S.IDLE, Fighter.S.RUN, Fighter.S.ATTACK]:
		if opp.can_be_hit():
			var r := rng.randf()
			if me.powered:
				if Rules.can_fusion(me.gauge) and me.gauge > 60 and r < 0.25: now.fusion1 = r < 0.12; now.fusion2 = r >= 0.12
				elif r < 0.6: now.punch = true
				else: now.kick = true
			elif r < 0.07 * level: now.action = true   # grab + throw
			elif r < 0.55: now.punch = true
			elif r < 0.85: now.kick = true
	if goal == "fight" and opp and dist > 2.5 and dist < 4.5 and rng.randf() < 0.01: now.jump = true
	if me.state == Fighter.S.JUMP and opp and dist < 2.0 and rng.randf() < 0.3: now.kick = true
	if me.is_on_wall() and me.state == Fighter.S.JUMP: now.jump = true
	if me.state == Fighter.S.JUMP and arena.nearest_pole(me.global_position, 1.0) != null and rng.randf() < 0.2: now.action = true
	# alternate presses so held buttons register as fresh presses
	for b in now.keys():
		if now[b] and press.get(b, false): now[b] = false
		press[b] = now[b]
	# move vector in the camera's screen space
	var local := cam_basis.inverse() * mv
	input.set_state(Vector2(local.x, local.z), now)

func _nearest_pole():
	var best = null; var bd := 1e9
	for p in arena.poles:
		var d: float = (p - me.global_position).length()
		if d < bd: bd = d; best = p
	return best

var pole_t := 0.0
var run_best := 99.0
var run_stuck := 0.0
var unstick_t := 0.0
var side := 1.0
var last_d := 99.0
var stuck_t := 0.0
var avoid_t := 0.0

func _choose_goal() -> void:
	if goal == "pole" and pole_t < 4.0: return   # stick to it for up to 4 s (tick drops it once swung)
	pole_t = 0.0
	var g := _nearest_gem()
	var opp := me.opponent
	if me.state == Fighter.S.CARRY: goal = "prop"; return
	if avoid_t > 0.0: goal = "fight"; return
	if g and not me.powered:
		var dg := me.global_position.distance_to(g.global_position)
		var dopp := opp.global_position.distance_to(g.global_position) if opp else 99.0
		if dg < dopp + 1.5 or me.gems >= 2: goal = "gem"; return
	if opp and opp.powered and not me.powered and rng.randf() < 0.4:
		goal = "retreat" if rng.randf() < 0.5 else "prop"; return
	if rng.randf() < 0.06: goal = "prop"; return
	if rng.randf() < 0.03 and _nearest_pole() != null: goal = "pole"; return
	goal = "fight"

func _nearest_gem() -> Gem:
	var best: Gem = null; var bd := 1e9
	for g in arena.gems:
		if g.age < 0.4: continue
		var d := me.global_position.distance_to(g.global_position)
		if d < bd: bd = d; best = g
	return best
