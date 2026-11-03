class_name Fighter
extends CharacterBody3D
## One fighter. Gameplay runs on an invisible capsule; the visible body is the ripped model
## (PSModel) when its files are present. There is no stand-in body.

signal damaged(f: Fighter, dmg: int)
signal gem_count_changed(f: Fighter)
signal powered_changed(f: Fighter)
signal knocked_out(f: Fighter)
signal fx(kind: String, pos: Vector3)

enum S { IDLE, RUN, JUMP, ATTACK, GRAB, CARRY, HITSTUN, DOWN, GETUP, TRANSFORM, POLE, KO, WIN }

const RUN_SPEED := 6.0
const POWER_RUN := 7.2
const JUMP_V := 9.5
const GRAVITY := 26.0
const WALL_JUMP_OUT := 6.5
const CAPSULE_R := 0.38
const CAPSULE_H := 1.75

var pid := 0
var char_id := "falcon"
var ctrl: PInput   # what the pad / CPU / tape says this frame
var ic := PInput.new()   # what the fighter acts on: last frame's pad (the original's extra frame of latency, logged)
var _last_in := [Vector2.ZERO, {}, {}]
var cam_basis := Basis.IDENTITY   # camera yaw basis for camera-relative movement
var opponent: Fighter
var arena: Node   # Arena
var hp := Rules.MAX_HP:
	set(v):
		if _HP_TRACE and v < hp: print("HPT %s f%d %d->%d st%d gst%d rx%s %s" % [char_id, Engine.get_physics_frames(), hp, v, state, gst, rx_on, str(get_stack().slice(1, 4).map(func(e): return "%s:%d" % [e.function, e.line]))])
		hp = v
static var _HP_TRACE := OS.has_environment("PS_HP_TRACE")
var gems := 0
var gauge := 0.0
var powered := false
var state := S.IDLE
var state_t := 0.0
var combo := ""
var cur_attack := ""
var attack_hit := false
var invuln := 0.0
var hitstop := 0.0
var carry: Node3D = null
var facing := Vector3(0, 0, 1)
var pole_center := Vector3.ZERO
var pole_angle := 0.0
var air_attacked := false
var model: Node3D = null
var last_hit_by: Fighter = null   # cinematics: who landed the final blow
var team := 0                      # Battle Royale: same team = no damage (2v2); 1v1 / free-for-all: own team each
var enemies: Array = []            # Battle Royale: every enemy still standing (the fight refreshes it); 1v1 uses opponent
var grabbed: Fighter = null
## Final Valgas (logged as the CPU in ladder fight 9): stands his ground, every attack runs in the game's Power Change
## attack state (11), never collects gems or transforms, and is not knocked about by hits
var boss := false
const BOSS_REACH := 2.5   # remaster tuning, only for moves the game hits with a projectile (no body spheres)
## The game's own hit data for this fighter (GameHits: hit steps, attack records, sphere sets off the disc)
var ghits: GameHits = null
var combo_hits := 0       # the game's hits-in-a-row counter (attacker +0x720E): its damage cut-off
var cpu_level := -1       # the game's CPU strength level when this fighter is an arcade CPU (-1 = none)
var _hit_mark := ""       # clip / hit id / arm frame already landed: the game hits each fighter once per armed id
var stats := {"hits": 0, "dmg_dealt": 0, "throws": 0, "objects_thrown": 0, "gems_picked": 0, "changes": 0,
	"sphere_hits": 0}   # sphere_hits: hits decided by the game's own spheres and frames

func setup(p_pid: int, p_char: String, p_ctrl: PInput) -> void:
	pid = p_pid; char_id = p_char; ctrl = p_ctrl
	boss = Roster.is_boss(p_char)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = CAPSULE_R + body_delta(p_char); cap.height = CAPSULE_H
	cs.shape = cap; cs.position.y = CAPSULE_H * 0.5
	add_child(cs)
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	collision_layer = 2; collision_mask = 1 | 2
	var m := PSModel.create_for(char_id, false)
	if m:
		model = m; add_child(m)
	var fl := PSModel.files(char_id)
	if not fl.is_empty(): ghits = GameHits.load_for(str(fl[0]))

## H-5: the game's per-fighter collision radius (player +0x258, fighter_radius.json, measured by fx-oom: Falcon 30 cm,
## Gunrock 60, Kraken 52, Valgas 50.4 ...) over Falcon's, added to the one capsule every fighter had (big fighters
## stood inside each other); the area walls / clamp already use the same delta (Arena.fighter_margin)
static var _body_r := {}
static func body_delta(id: String) -> float:
	if _body_r.is_empty() and FileAccess.file_exists("res://assets/fidelity/fighter_radius.json"):
		_body_r = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/fighter_radius.json"))
	return float((_body_r.get("delta_cm", {}) as Dictionary).get(id, 0.0)) * 0.01

## The original's body push (fx-cov BUG-45: dist_galuda f11 Falcon / Galuda 40 cm apart -> 78 = 30 + 48 on that same
## frame, both moved half the overlap; near_gunrock: Gunrock / Falcon 100 cm apart = no push, sum 90): after every
## fighter's frame, any two whose centres are closer than the sum of their radii (+0x258, fighter_radius.json) at about
## the same height are pushed apart along the line between them. Final Valgas: Falcon never gets closer than 150 cm on
## the disc (fx-fv), so his push radius is 120 (his +0x258 140 is not what pushes).
const PUSH_DY := 1.5
static func body_radius(id: String) -> float:
	if id == "finalvalgas": return 1.20
	body_delta(id)
	return float((_body_r.get("radius_cm", {}) as Dictionary).get(id, 30.0)) * 0.01

static func body_push(fs: Array) -> void:
	for i in fs.size():
		for j in range(i + 1, fs.size()):
			var a: Fighter = fs[i]; var b: Fighter = fs[j]
			if a.held_by or b.held_by or a.thr_on or b.thr_on: continue   # a throw places the victim itself
			if a.gst in [8, 15, 16] or b.gst in [8, 15, 16]: continue   # lying / getting up / KO'd: not measured, left alone
			if absf(a.global_position.y - b.global_position.y) > PUSH_DY: continue
			var d := b.global_position - a.global_position; d.y = 0
			var rs := body_radius(a.char_id) + body_radius(b.char_id)
			var l := d.length()
			if l >= rs: continue
			var n := d / l if l > 0.001 else a.facing
			var o := (rs - l) * 0.5
			# a ground attack's own travel (motions.json) shoves the other body the whole way and is not cut (disc: Jack's
			# k1/74 keeps 6.5 / 4.2 cm per frame with Falcon in contact, Falcon moves the same, moves_jack f22-27); bodies
			# moving by velocity (runs, stops, idle) split the overlap half each (1,800 logged contact frames, share 0.5)
			var ta := a._travel_push(); var tb := b._travel_push()
			var pa := a.global_position; var pb := b.global_position
			if a.boss: b.global_position += n * o * 2.0     # Final Valgas never moves (logged): the other takes it all
			elif b.boss: a.global_position -= n * o * 2.0
			elif ta and not tb: b.global_position += n * o * 2.0
			elif tb and not ta: a.global_position -= n * o * 2.0
			else:
				a.global_position -= n * o; b.global_position += n * o
			for k in 2:   # ... nor into a block / raised floor the original has at its feet' height (2v2 on Kraken's ship:
				# Ayame shoved 50 cm into the 1 m platform's cells at y 0, 4 frames over no floor of the original): stays put
				var f: Fighter = [a, b][k]; var was: Vector3 = [pa, pb][k]
				if f.arena and f.arena.has_method("wall_block") and f.arena.wall_block(f.global_position) and not f.arena.wall_block(was):
					f.global_position = Vector3(was.x, f.global_position.y, was.z)
			for f in [a, b]:   # a push never takes a body through the original's walls (4 fighters pressing one at an edge)
				if f.arena and f.arena.has_method("clamp_fighter"): f.arena.clamp_fighter(f)

## True while the fighter moves by a ground attack's own per-frame travel (the body push then moves only the other one)
func _travel_push() -> bool:
	return core_atk and state == S.ATTACK and not gmo_air

func defence() -> float:   # the game's per-fighter damage taken (0x0C32E078): Valgas 0.7, Final Valgas 0.5 ...
	return ghits.defence if ghits and ghits.ok else 1.0

## Current motion -> [hit-data key, the game's motion frame]. The game counts frames from 0 on the set_motion frame;
## the RAM-captured clips start one frame later (logged: Falcon's jab hand and kick foot sit at clip frame k exactly
## where the game's spheres sit at its frame k + 1, tests/hit_geom.gd vs hdA), so game frame = clip frame + 1.
func _motion() -> Array:
	if not (model is PSModel): return ["", 0]
	var m := model as PSModel
	if core_atk and GameHits.key_of(m.current_clip()) == gmo: return [gmo, gmo_f]   # the core's own counter (fx-mv / fx-reach)
	return [GameHits.key_of(m.current_clip()), int(m.clip_pos() * 60.0 + 0.001) + 1]

## The game's body spheres for the motion being played (its hit steps' body set; coarse set 10 when the motion has
## none and no logged default: the set the game uses standing and running)
func body_spheres() -> Array:
	if ghits == null or not ghits.ok or not (model is PSModel):
		return [[global_position + Vector3.UP * 0.9, 0.55]]
	var mo := _motion()
	var bs: int = ghits.at(mo[0], mo[1]).bset
	if bs < 0: bs = 10
	var out := ghits.world_spheres(ghits.body_sets, bs, (model as PSModel).skeleton(), self, 1)
	if out.is_empty(): out = ghits.world_spheres(ghits.body_sets, 0, (model as PSModel).skeleton(), self, 1)
	return out

func reset_round(pos: Vector3, face: Vector3) -> void:
	global_position = pos; velocity = Vector3.ZERO
	facing = face.normalized(); hp = Rules.MAX_HP; gems = 0; gauge = 0.0; rec_ceil = Rules.MAX_HP; rec_cnt = 0
	pc_on = false
	if powered and not boss: _set_powered(false)
	pc_g = 0; gauge = 0.0
	if boss: powered = true; gauge = Rules.GAUGE_MAX; pc_g = CorePC.GAUGE_FULL
	_drop_carry(false)
	set_state(S.IDLE); invuln = 0.0; hitstop = 0.0
	_apply_facing()
	if boss: _fv_reset()

func set_state(s: int) -> void:
	var prev := state
	state = s; state_t = 0.0
	if not _core_setting:
		gst_t = 0
		core_atk = false; hit_stop = 0; rx_on = false
		if thr_on and thr_victim and is_instance_valid(thr_victim) and thr_victim.held_by == self: thr_victim.held_by = null
		thr_on = false; held_by = null
		if model is PSModel: (model as PSModel).time_scale = 1.0
		gst = {S.IDLE: 0, S.RUN: 31, S.JUMP: 14, S.ATTACK: 11 if powered else 10, S.GRAB: 37, S.CARRY: 35,
			S.HITSTUN: 27, S.DOWN: 15, S.GETUP: 16, S.TRANSFORM: 23, S.POLE: 34, S.KO: 8, S.WIN: 21}.get(s, 0)
		if s == S.JUMP: air_move = Vector2(velocity.x, velocity.z).length() > 1.0
	var by: Fighter = last_hit_by if last_hit_by else opponent
	if s != S.HITSTUN and by: by.combo_hits = 0   # the game resets it when the hit reaction ends
	if model is PSModel:   # attacks and grabs travel with their clip's hip (root motion, psmodel.gd)
		(model as PSModel).root_motion = (s == S.ATTACK and cur_attack != "air") or s == S.GRAB
	if model:
		match s:
			S.IDLE:
				if prev == S.JUMP and model is PSModel: (model as PSModel).play_then("land", "idle")
				else: model.play("idle")
			S.RUN: model.play("run")
			S.JUMP:
				# logged: a standing jump plays k0/5 > 6, a jump with a direction held plays k0/10 (both land on k0/9)
				if model is PSModel and prev != S.JUMP and (model as PSModel).has_clip("jump_move") and Vector2(velocity.x, velocity.z).length() > 1.0:
					model.play("jump_move")
				elif model is PSModel and prev != S.JUMP: (model as PSModel).play_then("jump_start", "jump")
				else: model.play("jump")
			S.HITSTUN: model.play("hit")
			S.DOWN:
				if model is PSModel: (model as PSModel).play_then("down", "lying")
				else: model.play("down")
			S.GETUP: model.play("getup")
			S.KO:   # the original: the KO'd fighter stays in its knock-down > lying motion (k2/153 > k2/144); coming from DOWN
				# it is already in it (replaying the fall from its first frame popped him back up into the air)
				if model is PSModel and not (prev == S.DOWN and (model as PSModel).playing in ["down", "lying"]):
					(model as PSModel).play_then("down", "lying")
				elif not (model is PSModel): model.play("down")
			S.WIN: model.play("win")
			S.TRANSFORM: model.play("transform")
			S.CARRY:
				if model is PSModel and prev != S.CARRY: (model as PSModel).play_then("pick_up", "carry")
				else: model.play("carry")

func is_busy() -> bool:
	return state in [S.ATTACK, S.GRAB, S.HITSTUN, S.DOWN, S.GETUP, S.TRANSFORM, S.POLE, S.KO, S.WIN]

func can_be_hit() -> bool:
	return invuln <= 0.0 and state not in [S.DOWN, S.GETUP, S.KO, S.WIN] and (state != S.TRANSFORM or (pc_on and pc_kind == "rv"))

func _delay_input() -> void:
	ic.move = _last_in[0]; ic.held = _last_in[1]; ic.pressed = _last_in[2]
	if ctrl: _last_in = [ctrl.move, ctrl.held.duplicate(), ctrl.pressed.duplicate()]

## Health recovery, the disc's rule (fx-cov2 docs/HEALTH.md from 1ST_READ 0x0C055566 / 0x0C08E16C, scored on 96 logs:
## the tick exact on 700,111 quiet frames, the ceiling on 487 / 487 recoverable hits): a recoverable ceiling (+0x71D6)
## the health climbs back to, +1 when the u8 counter (+0x720F) runs out, then 40 again; the counter is not reset when
## nothing is pending (it wraps every 256 frames); a hit sets it to 40. Only in the fight phase (fight.gd recover_on).
const RECOVER_EVERY := 40
var rec_ceil := Rules.MAX_HP
var rec_cnt := 0
var recover_on := false           # fight.gd: true on fight-phase frames (the disc's tick runs only in round phase 3)

var _rec_set_f := -1               # the frame a hit set the counter: it doesn't count down that frame (the disc: +1 at
                                   # hit + 40 for both players, 210 / 210; P2 hit by P1 earlier in the same frame was at + 39)
func _recover_tick() -> void:
	if not recover_on: return
	if _rec_set_f == Engine.get_physics_frames(): return
	rec_cnt = (rec_cnt - 1) & 0xFF
	if rec_cnt == 0 and hp > 0 and hp < rec_ceil:
		hp += 1; rec_cnt = RECOVER_EVERY

## A hit's effect on the recovery (0x0C08E16C..0x0C08E2DE): a NEW combo's first hit forfeits what is still pending; an
## ordinary attack record (b4 type 0) takes int(d x 0.19999999) off the ceiling (d = the float damage), every other
## type (1 pole / air actions, 2 throws, 3 / 4 Power Change moves, 5 thrown objects / items) leaves nothing to recover
## (called with the damage already taken off: hp_before = the health the combo rule compares, as the disc does first)
func _recover_hit(dmg_f: float, rtype: int, attacker: Fighter, hp_before: int) -> void:
	if attacker and attacker.combo_hits == 1 and hp_before != rec_ceil: rec_ceil = hp_before
	if rtype == 0: rec_ceil = maxi(hp, rec_ceil - int(dmg_f * 0.19999999))
	else: rec_ceil = hp
	rec_cnt = RECOVER_EVERY; _rec_set_f = Engine.get_physics_frames()

func tick(dt: float) -> void:
	if model is PSModel and (model as PSModel).travel_on and not (core_atk and state == S.ATTACK):
		(model as PSModel).travel_on = false
	_delay_input()
	_recover_tick()
	if stun_quiet > 0:   # the stun meter refills after 180 quiet frames (assumed: docs/REACT.md)
		stun_quiet -= 1
		if stun_quiet == 0: stun = 20
	if boss and _fv_tick(): return   # Final Valgas (fx-fv2): his own fighter code
	if CORE and not boss and _pc_frame(): return
	if CORE and held_by:   # held in a throw: the thrower places him every row
		return
	if CORE and thr_on:
		_throw_tick()
		return
	if CORE and rx_on:
		_react_tick()
		return
	if CORE and state == S.POLE:
		_pole_core()
		return
	if CORE and wk_t >= 0:
		_wallkick_tick()
		return
	if CORE and core_atk and state == S.ATTACK:
		_core_attack_tick(dt)
		return
	if CORE and state in [S.IDLE, S.RUN, S.JUMP, S.CARRY] and hitstop <= 0.0 and not boss:
		_core_tick(dt)
		return
	if hitstop > 0.0:
		hitstop -= dt
		return
	state_t += dt
	invuln = maxf(0.0, invuln - dt)
	if boss:
		gauge = Rules.GAUGE_MAX
	elif powered and not CORE:   # (the core: _pc_frame ticks the gauge and starts the revert)
		if state not in [S.HITSTUN, S.DOWN]: gauge = Rules.drain_gauge(gauge, dt)   # the game pauses it in hit reactions
		if gauge <= 0.0 and state != S.ATTACK:
			_set_powered(false)
	var mv := _move_dir()
	var on_floor := is_on_floor()
	match state:
		S.IDLE, S.RUN:
			_ground_control(mv, dt)
			if not on_floor and not boss:
				set_state(S.JUMP)
		S.CARRY:
			_ground_control(mv, dt, 0.8)
			if model is PSModel and (model as PSModel).then_anim == "":
				model.play("carry_run" if Vector2(velocity.x, velocity.z).length() > 0.8 else "carry")
			if ic.is_pressed("punch") or ic.is_pressed("kick"):
				_throw_carry()
			elif ic.is_pressed("action"):
				_drop_carry(true)
		S.JUMP:
			velocity.x = lerpf(velocity.x, mv.x * _speed(), 4.0 * dt)
			velocity.z = lerpf(velocity.z, mv.z * _speed(), 4.0 * dt)
			if ic.is_pressed("jump") and is_on_wall():
				var n := get_wall_normal()
				velocity = Vector3(n.x, 0, n.z).normalized() * WALL_JUMP_OUT + Vector3.UP * JUMP_V * 0.95
				facing = Vector3(n.x, 0, n.z).normalized()
				fx.emit("walljump", global_position + Vector3.UP)
				# logged (attract demo): wall kick k2/206 (state 38, 8 frames) > k0/13 in the air > land k0/9
				if model is PSModel and (model as PSModel).has_clip("walljump"): (model as PSModel).play_then("walljump", "walljump_air")
			elif ic.is_pressed("action") and _try_pole():
				pass
			elif (ic.is_pressed("punch") or ic.is_pressed("kick")) and not air_attacked:
				air_attacked = true
				_start_attack("air")
			if on_floor and state_t > 0.05:
				air_attacked = false
				set_state(S.RUN if mv.length() > 0.1 else S.IDLE)
		S.ATTACK:
			_attack_update(dt)
		S.GRAB:
			velocity.x = 0; velocity.z = 0
			if state_t >= 0.3:
				_do_throw()
		S.HITSTUN:
			velocity.x = move_toward(velocity.x, 0, 12 * dt); velocity.z = move_toward(velocity.z, 0, 12 * dt)
			if state_t >= 0.32: set_state(S.IDLE)
		S.DOWN:
			# on the core's ground too: where the disc's floor has no remaster mesh under it (or the mesh is left out of
			# collision) is_on_floor() stays false, and a fighter knocked down outside the reaction machine lay there for
			# good (w9 ladders: 20-60 s stalls, Jack at (3.73, 0, 6.09), Falcon at (6.4, 0, 0.25), Falcon held 35 cm over
			# stg50's floor at (-0.19, 3.61)); the disc's lying state is timed, so 3 s down gets up whatever holds him
			var dg := is_on_floor()
			if not dg and _cg_on() and velocity.y <= 0.0:   # resting on the disc's measured floor (clamp_fighter holds him there)
				var gp := global_position
				dg = absf(arena.floor_y_at(gp.x, gp.z, gp.y + 0.05) - gp.y) <= 0.03
			if dg and state_t > 0.2:
				velocity.x = move_toward(velocity.x, 0, 20 * dt); velocity.z = move_toward(velocity.z, 0, 20 * dt)
			if hp <= 0:
				if dg and state_t > 0.4: set_state(S.KO)
			elif (state_t >= 1.05 and dg) or state_t >= 3.0:
				set_state(S.GETUP)
		S.GETUP:
			velocity.x = 0; velocity.z = 0
			if state_t >= 0.45:
				invuln = Rules.GETUP_INVULN
				set_state(S.IDLE)
		S.TRANSFORM:
			velocity = Vector3.ZERO
			if state_t >= tf_len:
				set_state(S.IDLE)
		S.POLE:
			_pole_update(dt)
		S.KO, S.WIN:
			velocity.x = move_toward(velocity.x, 0, 10 * dt); velocity.z = move_toward(velocity.z, 0, 10 * dt)
	if state != S.POLE and state != S.TRANSFORM:
		# H-1: an air attack the core hands over (no clip for its motion / Power Change) keeps the core's jump: the
		# original's 2 cm/frame^2 (72 m/s^2), not the old 26 m/s^2 that flew the core's 35.5 cm/frame launch to 8.7 m
		velocity.y -= (GRAV_CM * 0.01 * 3600.0 if CORE and state == S.ATTACK and cur_attack == "air" else GRAVITY) * dt
	if model is PSModel:   # root motion: the hip travel of the clip on display moves the body
		var rd := (model as PSModel).take_root_delta()
		if rd.length_squared() > 1e-8: move_and_collide(model.global_basis * rd)
	move_and_slide()
	if arena: arena.clamp_fighter(self)
	_apply_facing()
	if carry: carry.global_position = global_position + Vector3.UP * 2.05
	vcm = velocity / CM_S

func _speed() -> float:
	return POWER_RUN if powered else RUN_SPEED

func _move_dir() -> Vector3:
	var m := ic.move
	var v := cam_basis * Vector3(m.x, 0, m.y)
	v.y = 0
	return v.limit_length(1.0)

func _ground_control(mv: Vector3, dt: float, mult := 1.0) -> void:
	if boss:   # never walks or jumps; his CPU starts the logged attacks directly (boss_attack)
		velocity.x = 0; velocity.z = 0
		_face_opponent()
		return
	var target := mv * _speed() * mult
	velocity.x = move_toward(velocity.x, target.x, 40 * dt)
	velocity.z = move_toward(velocity.z, target.z, 40 * dt)
	if mv.length() > 0.1:
		facing = facing.slerp(mv.normalized(), minf(1.0, 14 * dt)).normalized()
		if state == S.IDLE: set_state(S.RUN)
	elif state == S.RUN:
		set_state(S.IDLE)
	if state == S.CARRY: return
	if ic.is_pressed("jump"):
		velocity.y = JUMP_V
		set_state(S.JUMP)
		return
	if powered and (ic.is_pressed("fusion1") or (ic.is_held("jump") and ic.is_pressed("punch"))) and Rules.can_fusion(gauge):
		_start_attack("fusion1"); return
	if powered and (ic.is_pressed("fusion2") or (ic.is_held("jump") and ic.is_pressed("kick"))) and Rules.can_fusion(gauge):
		_start_attack("fusion2"); return
	if ic.is_pressed("action"):
		if _try_grab(): return
		if _try_pickup(): return
		if _try_pole(): return
	if ic.is_pressed("punch"):
		if powered and Rules.can_drive(gauge): _start_attack("drive_p")
		elif velocity.length() > RUN_SPEED * 0.8 and state == S.RUN: _start_attack("dash")
		else: _start_attack("punch1")
	elif ic.is_pressed("kick"):
		if powered and Rules.can_drive(gauge): _start_attack("drive_k")
		else: _start_attack("kick1")

func _face_opponent() -> void:
	if opponent:
		var d := opponent.global_position - global_position; d.y = 0
		if d.length() > 0.05 and (d.length() < 6.0 or boss): facing = d.normalized()

func boss_attack(aname: String) -> void:
	if state == S.IDLE: _start_attack(aname)

var atk_k := 1.0   # attack timing scale: the move lasts as long as the game's own motion for it

func _start_attack(aname: String) -> void:
	cur_attack = aname; attack_hit = false; _hit_mark = ""
	atk_k = 1.0
	if model is PSModel:
		var clip_len: float = (model as PSModel).clip_length(aname)
		if clip_len > 0.1 and not aname.begins_with("fusion") and aname != "air":
			atk_k = clampf(clip_len / float(Rules.ATTACKS[aname].t2), 0.7, 2.5)
		if boss:   # the attack lasts the whole logged motion sequence (99 > 100 > 101 ...)
			atk_k = maxf(1.0, (model as PSModel).chain_length(aname) / float(Rules.ATTACKS[aname].t2))
	_face_opponent()
	if boss: pass
	elif aname.begins_with("drive"):
		gauge -= Rules.DRIVE_COST
	elif aname.begins_with("fusion"):
		gauge = 0.001
		fx.emit("fusion", global_position + Vector3.UP)
	var travels := model is PSModel and (model as PSModel).root_travel(aname) > 0.4   # the clip carries the lunge
	if aname == "dash" and not travels:
		velocity = facing * RUN_SPEED * 1.3 + Vector3(0, velocity.y, 0)
	if aname == "fusion2" and not travels:
		velocity = facing * 9.0
	set_state(S.ATTACK)
	if model: model.play(aname)

func _attack_update(dt: float) -> void:
	var a: Dictionary = Rules.ATTACKS[cur_attack]
	if cur_attack in ["dash", "fusion2"]:
		velocity.x = move_toward(velocity.x, 0, 6 * dt); velocity.z = move_toward(velocity.z, 0, 6 * dt)
	elif cur_attack != "air":
		velocity.x = move_toward(velocity.x, 0, 30 * dt); velocity.z = move_toward(velocity.z, 0, 30 * dt)
	if cur_attack in ["fusion1", "fusion2", "drive_p", "drive_k"]:
		_face_opponent()
	var t0: float = a.t0 * atk_k; var t1: float = a.t1 * atk_k; var t2: float = a.t2 * atk_k
	if _game_hit_update():
		pass   # the game's own spheres and frames decide this move's hits
	elif state_t >= t0 and state_t <= t1 and (not attack_hit or cur_attack.begins_with("fusion")):
		_check_hit(a)
	# chain the string (punch 1-2-3, kick 1-2) during recovery
	if state_t > t1 and state_t < t2:
		if cur_attack == "punch1" and ic.is_pressed("punch"): _start_attack("punch2"); return
		if cur_attack == "punch2" and ic.is_pressed("punch"): _start_attack("punch3"); return
		if cur_attack == "kick1" and ic.is_pressed("kick"): _start_attack("kick2"); return
		if cur_attack == "punch3" and ic.is_pressed("punch") and model is PSModel and (model as PSModel).has_clip("punch4"):
			_start_attack("punch4"); return   # four-punch strings (Wang-Tang k1/16 > 17 > 18 > 19, logged)
		if cur_attack == "kick2" and ic.is_pressed("kick") and model is PSModel and (model as PSModel).has_clip("kick3"):
			_start_attack("kick3"); return   # three-kick strings (Ayame k1/24 > 25 > 29, logged)
	if cur_attack == "air":
		if is_on_floor() and state_t > t0:
			air_attacked = false
			set_state(S.IDLE)
		return
	if state_t >= t2:
		set_state(S.IDLE)

## The game's own hit test: this fighter's live attack spheres (its motion's hit steps) against the opponent's body
## spheres (Battle Royale: every enemy's). Returns false when the motion has no attack spheres in the game's data
## (projectile moves: _check_hit).
func _game_hit_update() -> bool:
	if ghits == null or not ghits.ok: return false
	var mo := _motion()
	if not ghits.has_move(mo[0]) or ghits.active_window(mo[0]).x < 0: return false
	var st := ghits.at(mo[0], mo[1])
	if st.hit == 0 or st.aset == 0: return true
	var mark := "%s/%d/%d" % [mo[0], st.hit, st.arm]
	if st.held and pc_on: mark += "/%d" % (pc_i / 5)   # a step the code holds (0-255: Jack's Fusion X k1/107, the motion frame
	# never moves) is re-armed by the code every 5 frames (code_hits' rule): 14 hits on the disc as his spinning bar passes
	if mark == _hit_mark: return true
	var att := ghits.world_spheres(ghits.atk_sets, st.aset, (model as PSModel).skeleton(), self)
	if att.is_empty(): return true
	for o in (enemies if enemies.size() > 0 else [opponent]):
		var t: Fighter = o
		if not t or not t.can_be_hit() or not GameHits.overlap(att, t.body_spheres()): continue
		_hit_mark = mark
		_land_hit(t, ghits.record(st.hit), Rules.ATTACKS.get(cur_attack, Rules.ATTACKS.punch1), st.hit)
		stats.sphere_hits += 1
	return true

## Damage of one landed hit with the game's formula (Rules.game_damage); rec = the game's attack record
func _hit_damage(target: Fighter, rec: Dictionary, fallback: int) -> int:
	var base := int(rec.get("dmg", fallback))
	var hits_in_row := combo_hits if target.boss else combo_hits + 1   # hits on Final Valgas don't count
	return Rules.game_damage(base, target.defence(), hits_in_row, gems, powered, target.powered,
		cpu_level, target.cpu_level, int(rec.get("type", 0)))

func _land_hit(target: Fighter, rec: Dictionary, a: Dictionary, hid := -1) -> void:
	attack_hit = true
	var dmg := _hit_damage(target, rec, a.dmg)
	var hits_in_row := combo_hits if target.boss else combo_hits + 1
	var dmg_f := Rules.game_damage_f(int(rec.get("dmg", a.dmg)), target.defence(), hits_in_row, gems, powered, target.powered,
		cpu_level, target.cpu_level, int(rec.get("type", 0)))
	if not target.boss: combo_hits = mini(combo_hits + 1, 99)
	var rt := int(rec.get("type", 0))
	if powered and rt == 0: rt = 3   # a Power Change attacker's hits never come back (HEALTH.md: 645 logged)
	target.receive_hit(dmg, a.kb, a.down, global_position, self, hid, dmg_f, rt)
	var rb := _rx_record(self, hid)
	_rx_stop = int(rb[2]) if rb.size() == 20 else -1   # the attacker's hit-stop = the record's (0x0C08DBC8)
	hitstop = 0.07 if not a.down else 0.11
	stats.hits += 1; stats.dmg_dealt += dmg

func _check_hit(a: Dictionary) -> void:
	for o in (enemies if enemies.size() > 0 else [opponent]):   # Battle Royale: a swing can catch anyone in front
		_check_hit_on(o, a)

func _check_hit_on(target: Fighter, a: Dictionary) -> void:
	if not target or not target.can_be_hit(): return
	var k := BOSS_REACH if boss else 1.0
	var hp_pos: Vector3 = global_position + facing * a.reach * k + Vector3.UP * a.h
	var opp: Vector3 = target.global_position + Vector3.UP * clampf(hp_pos.y - target.global_position.y, 0.3, 1.5)
	if hp_pos.distance_to(opp) <= a.r * k + CAPSULE_R:
		attack_hit = true
		var rec := {}
		if ghits and ghits.ok:   # projectile moves: the record the motion's steps arm (Power Missile = hit 112 ...)
			var key: String = _motion()[0]
			var hid := ghits.first_hit(key)
			if hid: rec = ghits.record(hid).duplicate()
			if ghits.proj_base.has(key):   # logged: its projectile carries another base (Valgas k1/101 = 20)
				rec["dmg"] = int(ghits.proj_base[key])
		var dmg := _hit_damage(target, rec, a.dmg)
		if not target.boss: combo_hits = mini(combo_hits + 1, 99)
		if cur_attack.begins_with("fusion") and rec.is_empty():
			dmg = maxi(1, int(dmg / 4.0))   # fusions hit repeatedly over their active window
		target.receive_hit(dmg, a.kb, a.down, global_position, self)
		hitstop = 0.07 if not a.down else 0.11
		stats.hits += 1; stats.dmg_dealt += dmg

## dmg_f = the float damage (-1: dmg), rtype = the attack record's type (b4; -1: from the attacker's state)
func receive_hit(dmg: int, kb: float, down: bool, from: Vector3, attacker: Fighter, hid := -1, dmg_f := -1.0, rtype := -1) -> bool:
	if not can_be_hit(): return false
	if attacker: last_hit_by = attacker
	if rtype < 0: rtype = 2 if (attacker and attacker.state == S.GRAB) else (3 if attacker and attacker.powered else 0)
	if dmg_f < 0.0: dmg_f = float(dmg)
	var hp0 := hp
	hp = Rules.apply_damage(hp, dmg)
	_recover_hit(dmg_f, rtype, attacker, hp0)
	if powered and not boss:   # the game: d / 240 x 1800 on a recoverable hit, x 5520 on the others (0x0C08E2BC, HEALTH.md)
		pc_g = maxi(0, pc_g - int(dmg_f / 240.0 * (1800.0 if rtype == 0 else 5520.0))); _pc_sync()
	damaged.emit(self, dmg)
	fx.emit("hit_big" if down else "hit", global_position + Vector3.UP * 1.1)
	hitstop = 0.07 if not down else 0.11
	var dir := global_position - from; dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else -facing
	facing = -dir
	if boss and _fv_on():   # Final Valgas (fx-fv2): his reactions are health thresholds
		_fv_hit(); return true
	if boss:   # no knockback or reaction motion was logged for him: damage only, down when KO'd
		if hp <= 0:
			set_state(S.DOWN); knocked_out.emit(self)
		return true
	if carry: _drop_carry(true)
	if item: _item_drop()   # fx-item2 hook: a hit drops the held item
	if arena and arena.drop_f >= 0:   # 1-on-1: the disc's rule (0x0C08E980): the hit record's byte 16 & 4 = 1 gem, & 8 = 2
		var n := _spill_n(attacker, hid)
		if n > 0:
			gems -= n; gem_count_changed.emit(self)
			arena.spill_from(self, (attacker.global_position if attacker else from) - global_position, n)
	else:
		var lost := Rules.gems_dropped(gems, down or hp <= 0, powered, attacker != null and attacker.char_id == "valgas")
		if lost > 0:
			gems -= lost
			gem_count_changed.emit(self)
			if arena: arena.spill_gems(global_position, lost)
	if CORE and react_start(attacker, hid, from):
		hitstop = 0.0   # the machine freezes him itself (rec[2] - 2 rows)
		if hp <= 0: knocked_out.emit(self)
		return true
	if down or hp <= 0:
		velocity = dir * kb + Vector3.UP * 6.0
		set_state(S.DOWN)
		if hp <= 0: knocked_out.emit(self)
	else:
		velocity = dir * kb
		set_state(S.HITSTUN)
	return true

func _try_grab() -> bool:
	if not opponent or not opponent.can_be_hit() or not opponent.grounded(): return false
	var d := opponent.global_position - global_position; d.y = 0
	if d.length() > 1.25 or d.normalized().dot(facing) < 0.3: return false
	facing = d.normalized()
	if CORE and _core_grab(opponent): return true
	grabbed = opponent
	set_state(S.GRAB)
	if model: model.play("grab")
	opponent.velocity = Vector3.ZERO
	opponent.set_state(S.HITSTUN)
	return true

func _do_throw() -> void:
	var a: Dictionary = Rules.ATTACKS.throw
	var victim: Fighter = grabbed if grabbed else opponent
	grabbed = null
	if victim and victim.global_position.distance_to(global_position) < 1.8:
		victim.invuln = 0.0
		# the game's throw: type-2 records (no defence, combo cut or bonus), the logged total in one hit
		var dmg := Rules.game_damage(int(Rules.THROW_TOTAL.get(char_id, a.dmg)), victim.defence(), 1, gems, powered,
			victim.powered, cpu_level, victim.cpu_level, 2)
		victim.receive_hit(dmg, a.kb, true, global_position - facing, self)
		stats.throws += 1; stats.dmg_dealt += dmg; stats.hits += 1
	set_state(S.IDLE)

func _try_pickup() -> bool:
	if not arena: return false
	var p: Node3D = arena.nearest_prop(global_position, 1.45 if CORE else 1.4)   # the disc lifted chair 32 from 144 cm (fx-cpu2)
	if not p: return false
	carry = p
	p.call("pick_up", self)
	if CORE:   # the original: state 35, k2/219 for 18 frames, then the carry (core states with k2/220 / k2/221)
		_carry_from = p.global_position
		var d := p.global_position - global_position; d.y = 0
		if d.length() > 0.05: facing = d.normalized(); head = _ang(facing)
		_gset(35, S.CARRY)
		_apply_facing()
		return true
	set_state(S.CARRY)
	return true

func _throw_carry() -> void:
	if not carry: return
	if CORE and _core_throw(): return
	_face_opponent()
	carry.call("throw_from", self, facing * 13.0 + Vector3.UP * 3.0)
	carry = null
	stats.objects_thrown += 1
	set_state(S.IDLE)
	if model: model.play("throw")

func _drop_carry(_fall: bool) -> void:
	if not carry: return
	carry.call("drop", global_position + facing * 0.8)
	carry = null
	if state == S.CARRY: set_state(S.IDLE)

## Poles (docs/OBJ.md 1, fx-obj: decoded from 1ST_READ and scored on the disc's 48 CPU logs). Catch (air handler
## 0x0C093EE8 > 0x0C09FE68): airborne + the ACTION press + a pole touching me -> state 34 (init 0x0C0A0370): heading =
## toward the pole axis, snapped 10 cm short of it, velocity 0, k2/211 then the hang loop k2/212. Hanging (0x0C0968A0):
## jump = let go (state 5), punch / kick = the swing (state 10 kind 7, 0x0C064152): k1/150 on the axis for 10 frames
## (Ryoma / Wang-Tang 18), then (0x0C06428A) heading = toward the opponent and the hop solver 0x0C0641A0: vy0 35,
## g 3.5 (Galuda 45 / 2.8), D = the horizontal distance (+100 cm Gunrock), vy0 halved under 200 cm, D in [1, 800],
## t = vy0 / g, H = (vy0 t + g t^2) / 2, T = t + sqrt(2 (H + |dy|) / g), horizontal speed D / T; k1/151 until the floor
## (its attack set from motion frame 16). Landing (0x0C064448): turned round (not Wang-Tang); connected = the normal
## landing k0/9 (Rouge k1/152), missed = k1/152 (35 frames); Galuda always k1/152; Gunrock k1/152 (+ a camera shake).
## Kraken's own flight (vy 8) is not decoded yet: he uses the shared one.
const POLE_CATCH_R := 0.9
const POLE_SNAP_CM := 10.0
const POLE_LAND_F := 35
var pole_sub := 0                 # 0 catch / hang, 1 k1/150 on the axis, 2 k1/151 flight, 3 k1/152 landing
var pole_t := 0
var pole_v := Vector3.ZERO        # cm/frame
var pole_g := 3.5
var pole_hit := false

func _try_pole() -> bool:
	if not arena or boss or not (model is PSModel): return false
	var p = _mv_pole_catch()   # fx-mv BUG-50: the disc's reach (150 cm in the air, the body window), feet clamped
	if p == null: return false
	pole_center = p
	var to := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
	var h := _ang(to) if to.length() > 0.001 else _ang(facing)
	facing = _dir(h)
	global_position = Vector3(p.x, global_position.y, p.z) - _dir(h) * POLE_SNAP_CM * 0.01
	velocity = Vector3.ZERO; vcm = Vector3.ZERO; _vel_out = velocity
	pole_sub = 0; pole_t = 0; pole_hit = false
	_core_setting = true
	state = S.POLE; state_t = 0.0
	_core_setting = false
	gst = 34; gst_t = 0; air_attacked = false
	(model as PSModel).root_motion = false
	_gplay(2, 211)
	_apply_facing()
	return true

func _pole_core() -> void:
	state_t += 1.0 / 60.0
	invuln = maxf(0.0, invuln - 1.0 / 60.0)
	gst_t += 1; pole_t += 1
	if hit_stop > 0:
		hit_stop -= 1
		if model is PSModel: (model as PSModel).time_scale = 0.0
		return
	if model is PSModel: (model as PSModel).time_scale = 1.0
	match pole_sub:
		0:   # hanging
			velocity = Vector3.ZERO; vcm = Vector3.ZERO; _vel_out = velocity
			if pole_t == 2: _gplay(2, 212)
			if ic.is_pressed("jump"):   # let go: a jump the stick's way (else sideways off the pole)
				var mv := _move_dir()
				air_move = mv.length() > 0.1; air_ctrl = false
				head = _ang(mv) if air_move else _wrap(_ang(facing) + PI * 0.5)
				_gset(5, S.JUMP)
				return
			if ic.is_pressed("punch") or ic.is_pressed("kick"):
				pole_sub = 1; pole_t = 0; gst = 10; gst_t = 0
				global_position = Vector3(pole_center.x, global_position.y, pole_center.z) - facing * 0.001
				_gplay(1, 150)
		1:   # k1/150 on the axis
			if pole_t >= (18 if char_id in ["ryoma", "wangtang"] else 10):
				var vy0 := 45.0 if char_id == "galuda" else 35.0
				pole_g = 2.8 if char_id == "galuda" else 3.5
				var d := Vector3.ZERO; var dy := 0.0
				if opponent:
					d = opponent.global_position - global_position; dy = absf(d.y) * 100.0; d.y = 0
				var dc := d.length() * 100.0 + (100.0 if char_id == "gunrock" else 0.0)
				if dc < 200.0 and vy0 > 20.0: vy0 *= 0.5
				dc = clampf(dc, 1.0, 800.0)
				var t := vy0 / pole_g
				var hh := (vy0 * t + pole_g * t * t) * 0.5
				var tt := t + sqrt(2.0 * (hh + dy) / pole_g)
				if d.length() > 0.001: facing = d.normalized()
				pole_v = facing * (dc / tt) + Vector3.UP * vy0
				pole_sub = 2; pole_t = 0
				cur_attack = "pole"; attack_hit = false; _hit_mark = ""
				_gplay(1, 151)
		2:   # k1/151: the hop at the opponent
			_core_move(pole_v, false)
			pole_v.y -= pole_g
			var before: int = int(stats.hits)
			_game_hit_update()
			if stats.hits > before:
				pole_hit = true; hit_stop = _rx_stop if _rx_stop >= 0 else HITSTOP_ATK
			if grounded() and pole_t > 1:
				if char_id != "wangtang": facing = -facing
				if pole_hit and char_id not in ["rouge", "galuda", "gunrock"]:
					_gset(6, S.IDLE); gst = 6
				else:
					pole_sub = 3; pole_t = 0; vcm = Vector3.ZERO
					_gplay(1, 152)
		3:   # k1/152
			_core_move(Vector3(0, -GRAV_CM if not grounded() else 0.0, 0), grounded())
			if pole_t >= POLE_LAND_F: _gset(0, S.IDLE)
	_apply_facing()

## The remaster's old orbit model, for the non-core path only (CORE is on: unused)
func _pole_update(_dt: float) -> void:
	set_state(S.IDLE)

## Wall kick (docs/OBJ.md 2): in the air, nothing held, once per airtime, jump pressed with the stick held, touching a
## wall or a stage object at rest -> state 38 (0x0C0A0984): k2/206 frozen for 8 frames facing into the wall along the
## nearest axis; punch / kick in that time = an air attack facing away; else (0x0C0971CE) turned away and state 5 sub 3:
## k0/13, vy 25 (table [10]), 2.0 cm/frame out (table [11]) plus the jump's air control, the fighter's jump gravity [6].
var wk_used := false
var wk_t := -1
var wk_h := 0.0

func _core_wallkick() -> bool:
	var n := Vector3.ZERO
	if _hit_wall(): n = _wall_normal()
	elif arena and arena.has_method("nearest_prop"):
		var o: Node3D = arena.nearest_prop(global_position, 0.6)
		if o: n = global_position - o.global_position
	n.y = 0
	if n.length() < 0.01: return false
	var into := -n.normalized()
	wk_h = 0.0 if absf(into.z) >= absf(into.x) and into.z >= 0 else (PI if absf(into.z) >= absf(into.x) else (PI * 0.5 if into.x > 0 else -PI * 0.5))
	wk_used = true; wk_t = 0
	vcm = Vector3.ZERO; velocity = Vector3.ZERO; _vel_out = velocity
	facing = _dir(wk_h); gst = 38; gst_t = 0
	_gplay(2, 206)
	_apply_facing()
	return true

func _wallkick_tick() -> void:
	state_t += 1.0 / 60.0
	gst_t += 1; wk_t += 1
	vcm = Vector3.ZERO; velocity = Vector3.ZERO; _vel_out = velocity
	if ic.is_pressed("punch") or ic.is_pressed("kick"):   # an air attack off the wall, facing away
		wk_t = -1; facing = -facing; head = _ang(facing); air_move = false; air_attacked = true
		gst = 5; gst_t = 2
		if _core_attack("AX" if ic.is_pressed("punch") else "AY"): return
		_gset(5, S.JUMP); gst_t = 2
		return
	if wk_t >= 8:
		wk_t = -1
		facing = -facing; head = _ang(facing)
		air_move = false; air_ctrl = false
		_gset(5, S.JUMP)
		gst_t = 2   # past the jump's own first-frame launch: this kick-off sets its own
		vcm = facing * _mv(11) + Vector3.UP * _mv(10)
		_gplay(0, 13)
		_vel_out = vcm * CM_S; velocity = _vel_out
	_apply_facing()

## --- Power Change (fx-pc; docs/PC.md "Port"): the original's own rows from game/assets/fidelity/pc_moves.json
## (CorePC). Gems: picked up only with the gauge at 0, fewer than 3 held, not in PC (0x0C09CB20); the transform
## starts the frame the third gem counts from the logged states (CorePC.TF_FROM), plays the logged state-23 rows
## (k3/8 130 f; Wang-Tang / Jack k3/8 > k3/11; air k3/11) and swaps the form + sets the gauge to 2400 on the row the
## original's PC flag turns on (the per-fighter morph frame). Gauge -1 per frame in round phase 3 only. Drives = k1/16
## for one frame, then the logged drive rows with the move's own cost on its logged row; Fusions = their logged rows,
## the whole gauge on theirs, ending by themselves. Revert when the gauge is 0 outside states 10 / 11 / 23: the logged
## k3/9 > k0/9 (Ryoma / Gunrock k3/9 > k3/10) rows; the form and the gems go back on the row the flag turns off.
var tf_len := 130.0 / 60.0   # the remaster's old transform (CORE off)
var pc_g := 0            # the gauge in the game's units (0..2400); gauge = pc_g / 24 for the HUD / CPU (0..100)
var pc_on := false       # a Power Change timeline owns the fighter
var pc_kind := ""        # "tf" transform | "rv" revert | "atk" Drive / Fusion
var pc_name := ""        # X / Y / AX / AY / FX / FY
var pc_rows: Array = []
var pc_i := 0
var pc_fr := 0           # the motion frame on display (the log's fr)
var pc_ref := 0.0        # facing angle the move started with (its travel rows are in that frame)
var pc_cost: Array = []
var pc_exit := 0
var pc_vy := 0.0
var pc_hold := 0         # extra hold rows (kept 0: the logged rows hold where the original holds)
var _pc_gst := -1
var _pc_state := -1

func _pc_sync() -> void:
	gauge = float(pc_g) / CorePC.UNITS

## Gems a hit knocks out (0x0C08E980): health >= 0, not in Power Change, 1 <= gems < 3, the hit record's byte 16:
## & 4 = 1, & 8 = 2 (ITEMS.md 4)
func _spill_n(attacker: Fighter, hid: int) -> int:
	if hp < 0 or powered or gems < 1 or gems >= Rules.GEMS_IN_PLAY: return 0
	if item_react_rec.size() == 20: return mini(gems, 2 if item_react_rec[16] & 8 else (1 if item_react_rec[16] & 4 else 0))   # fx-item2 hook: an item's record
	if attacker == null or attacker.ghits == null or not attacker.ghits.ok or hid < 0: return 0
	var raw := str(attacker.ghits.record(hid).get("raw", ""))
	if raw.length() < 34: return 0
	var b16 := raw.substr(32, 2).hex_to_int()
	return mini(gems, 2 if b16 & 8 else (1 if b16 & 4 else 0))

func can_take_gem() -> bool:
	return not boss and not powered and pc_g <= 0 and gems < Rules.GEMS_IN_PLAY and not (pc_on and pc_kind == "tf")

func pick_gem() -> void:
	if not can_take_gem(): return
	gems += 1
	stats.gems_picked += 1
	gem_count_changed.emit(self)
	if CORE: _pc_trigger()
	elif Rules.should_power_change(gems): _set_powered(true)

## the form change itself (the transform's morph row / the revert's swap row; a KO in PC drops it at once, 0x0C0A167C)
func _set_powered(on: bool) -> void:
	var was := powered
	powered = on
	if on:
		pc_g = CorePC.GAUGE_FULL; _pc_sync()
		if not was: stats.changes += 1
		if not was and arena and arena.drop_f >= 0: arena.queue_gems([0, 1, 2])   # the disc queues all 3 (ITEMS.md 4)
		_drop_carry(false)
		if not CORE:   # the remaster's old path (CORE off): straight into the transform state
			gems = 0
			set_state(S.TRANSFORM)
			invuln = 130.0 / 60.0
		fx.emit("transform", global_position + Vector3.UP)
	else:
		pc_g = 0; _pc_sync()
		gems = 0   # the original clears +0x7230 / +0x7231 when the form changes back (0x0C095A5E)
		if was and arena and arena.drop_f < 0 and arena.has_method("scatter_gems"): arena.scatter_gems(Rules.GEMS_IN_PLAY)   # Battle Royale
	if model and model.has_method("set_form"):
		var pm := model as PSModel
		var clip := pm.current_clip() if pm else ""
		var at := pm.clip_pos() if pm else 0.0
		model.set_form(on)
		if pm and pc_on:   # keep the motion and its frame across the swap (the original's model swap keeps both)
			var key := GameHits.key_of(clip)
			if key.length() == 6:
				_pc_show(int(key.substr(1, 1)), int(key.substr(3, 3)))
				var tr: AnimationTree = pm.trees.get(pm.form)
				if tr and tr.is_inside_tree() and at > 0.0: tr.advance(at)
	gem_count_changed.emit(self)
	powered_changed.emit(self)

## the transform the frame the third gem counts (pick-up or a tape's @gems), from the states the logs show
func _pc_trigger() -> bool:
	if boss or powered or pc_on or gems < Rules.GEMS_IN_PLAY or not CorePC.fight_on(self): return false
	if held_by or thr_on: return false
	if gst not in CorePC.TF_FROM: return false
	var air := gst in [4, 5, 14] or not grounded()
	var rows := CorePC.chain(char_id, "tf", air)
	if rows.is_empty(): return false
	if rx_on: rx_on = false   # lying / getting up: cut (logged)
	core_atk = false; hit_stop = 0
	_drop_carry(false)
	_pc_begin("tf", "", rows)
	return true

func _pc_begin(kind: String, nm: String, rows: Array) -> void:
	if item and kind == "tf": _item_drop(false)   # fx-item2 hook: the transform lets go of the item (disc CPU logs: k2/203 / 204 > k3/8 > k0/0)
	pc_kind = kind; pc_name = nm; pc_rows = rows; pc_i = 0; pc_hold = 0
	pc_ref = _ang(facing)
	var mv := CorePC.move(char_id, nm) if kind == "atk" else {}
	pc_cost = mv.get("cost", []) if mv.get("cost") != null else []
	pc_exit = int(mv.get("exit", 0)); pc_vy = float(mv.get("vy", 0.0))
	pc_on = true
	var coarse := S.ATTACK if kind == "atk" else S.TRANSFORM
	_core_setting = true
	state = coarse; state_t = 0.0
	_core_setting = false
	gst = 11 if kind == "atk" else 23; gst_t = 0
	vcm = Vector3.ZERO; velocity = Vector3.ZERO
	if model is PSModel:
		(model as PSModel).root_motion = false; (model as PSModel).time_scale = 1.0
	if kind == "atk":
		cur_attack = {"X": "drive_p", "AX": "drive_p", "Y": "drive_k", "AY": "drive_k", "FX": "fusion1", "FY": "fusion2"}.get(nm, "drive_p")
		attack_hit = false; _hit_mark = ""
		if nm.begins_with("F"): fx.emit("fusion", global_position + Vector3.UP)
	if kind == "tf": invuln = float(rows.size()) / 60.0
	_pc_row(true)
	if kind == "atk": _shots().begin(nm); _shots().spawn(0)
	_pc_gst = gst; _pc_state = state

## Drive / Fusion by name from the free states (true when it started)
func _pc_attack(nm: String) -> bool:
	if not powered or pc_on or boss or carry: return false
	var mv := CorePC.move(char_id, nm)
	var rows: Array = mv.get("rows", [])
	if rows.is_empty(): return false
	core_atk = false
	_pc_begin("atk", nm, rows)
	return true

## the row on display: motion, its frame, the PC flag (morph / swap), the gauge events, the body's travel
func _pc_row(first: bool) -> void:
	var r: Array = pc_rows[pc_i]
	var k := int(r[0]); var m := int(r[1])
	var prev: Array = pc_rows[pc_i - 1] if pc_i > 0 else []
	var changed := first or prev.is_empty() or int(prev[0]) != k or int(prev[1]) != m
	if first and pc_kind == "atk" and k != 1: changed = false   # a Fusion's first row keeps the old motion
	if changed: _pc_show(k, m)
	if model is PSModel:   # holds (the same motion frame twice) stand still like the original's
		(model as PSModel).time_scale = 0.0 if (not changed and not prev.is_empty() and int(prev[2]) == int(r[2])) else 1.0
	pc_fr = int(r[2])
	var want := int(r[6]) == 1
	if want != powered and pc_kind != "atk": _set_powered(want)
	if pc_kind == "atk" and pc_cost.size() == 2 and int(pc_cost[0]) == pc_i:
		var c := int(pc_cost[1])
		pc_g = 0 if c < 0 else maxi(0, pc_g - c)
		_pc_sync()
	if first: return
	if pc_kind == "atk": _shot_turn(); _pc_spin()
	var f := _dir(pc_ref); var sd := Vector3(f.z, 0, -f.x)
	var d := f * float(r[3]) + sd * float(r[4]) + Vector3.UP * float(r[5])
	vcm = d
	_core_move(d, grounded())

## the motion on display from this frame (the original never blends: no cross-fade, like flow_pose)
func _pc_show(k: int, m: int) -> void:
	_gplay(k, m)
	if not (model is PSModel): return
	var pm := model as PSModel
	var tr: AnimationTree = pm.trees.get(pm.form)
	var want := pm.clip_for(pm.playing)
	if tr and tr.is_inside_tree() and want != "" and pm.current_clip() != want:
		(tr.get("parameters/playback") as AnimationNodeStateMachinePlayback).start(want, true); tr.advance(0.0)

func _pc_end() -> void:
	pc_on = false
	var kind := pc_kind
	if model is PSModel: (model as PSModel).time_scale = 1.0
	if kind == "atk" and pc_exit in [5, 14] and not grounded():
		air_move = false; air_ctrl = false; air_attacked = true
		_gset(5, S.JUMP); gst_t = 2
		vcm.y = pc_vy   # the logged speed the fall starts from (pc_table.py: next row's vy + the 2 the core takes off)
	elif kind == "atk" and pc_exit == 6:
		_gset(6, S.IDLE); gst = 6
	elif not grounded():
		_gset(5, S.JUMP); gst_t = 2
	else:
		_gset(0, S.IDLE)
	if kind == "tf": invuln = 0.0

## Every frame first (Fighter.tick): the gauge, the revert / transform triggers, Fusion presses, the timeline.
## True = the Power Change timeline used this frame.
func _pc_frame() -> bool:
	if _shot_rx.size() == 4 and Engine.get_physics_frames() > int(_shot_rx[3]): _shot_react()
	if shots: shots.tick()
	if pc_on and (gst != _pc_gst or state != _pc_state):   # a hit / throw / the round flow took the fighter
		pc_on = false
		if model is PSModel: (model as PSModel).time_scale = 1.0
	var run := CorePC.fight_on(self)
	# the player tick checks the revert (0x0C0934DC) before it takes this frame's 1 off the gauge (0x0C093528):
	# logged, the gauge shows 0 for one free frame before state 23
	var busy := held_by != null or thr_on or rx_on
	if powered and hp <= 0 and not pc_on:   # KO'd: the form drops at once, no revert motion (0x0C0A167C, PC.md)
		_set_powered(false)
		return false
	if not pc_on and not busy and powered and pc_g <= 0 and run and gst not in CorePC.NO_REVERT:
		var air := gst in [4, 5, 14] or not grounded()
		var rows := CorePC.chain(char_id, "rv", air)
		if not rows.is_empty():
			core_atk = false
			_drop_carry(false)
			_pc_begin("rv", "", rows)
			return true
		_set_powered(false)
		return false
	if powered and run and pc_g > 0:
		pc_g -= 1; _pc_sync()
	if busy:
		if not powered and gems >= Rules.GEMS_IN_PLAY and rx_on and gst in [15, 16]: return _pc_trigger()
		return false
	if not pc_on:
		if not powered and gems >= Rules.GEMS_IN_PLAY and _pc_trigger(): return true
		# Fusions: A+X / A+Y on the ground (before the jump the core would start on A)
		if powered and gst in CorePC.GROUND_FREE and not carry:
			var fx1 := ic.is_pressed("fusion1") or (ic.is_held("jump") and ic.is_pressed("punch"))
			var fx2 := ic.is_pressed("fusion2") or (ic.is_held("jump") and ic.is_pressed("kick"))
			if (fx1 and _pc_attack("FX")) or (fx2 and _pc_attack("FY")): return true
		return false
	# the timeline
	state_t += 1.0 / 60.0
	gst_t += 1
	invuln = maxf(0.0, invuln - 1.0 / 60.0)
	if pc_hold > 0:
		pc_hold -= 1
		if model is PSModel: (model as PSModel).time_scale = 0.0
		return true
	pc_i += 1
	if pc_i >= pc_rows.size():
		_pc_end()
		return true
	_pc_row(false)
	if pc_kind == "atk":   # no extra hit-stop: the logged rows already hold where the original holds (a Drive's
		# projectile hit never stopped its thrower in the logs; Ryoma's Fusion k1/108 holds fr 25 / 140 by itself)
		_shots().spawn(pc_i)
		if not _game_hit_update() and not PCShots.has_shots(char_id, pc_name):
			var a: Dictionary = Rules.ATTACKS.get(cur_attack, Rules.ATTACKS.drive_p)
			if state_t >= float(a.t0) and state_t <= float(a.t1) and (not attack_hit or cur_attack.begins_with("fusion")):
				_check_hit(a)
		hitstop = 0.0
	_apply_facing()
	_pc_gst = gst; _pc_state = state
	return true

func _apply_facing() -> void:
	if model and facing.length() > 0.01:
		model.rotation.y = atan2(facing.x, facing.z)

## ---------------------------------------------------------------------------------------------------------------
## Movement states (fx-mv; docs/fx-mv.md): the disc's ACTION button with nothing in reach, the curved turn run (state
## 7), the vault (17), the ledge hang (36) and the pole catch rule, decoded from 1ST_READ and diffed by tape.
## BUG-53: the ACTION input (0x0C0A22D6) = punch pressed with kick held or kick pressed with punch held (pad B = both).
## Ground (states 0 / 2 / 31 / 32 handlers): the action list (0x0C0A2490: drop / grab / pick-up ...) first, and when it
## takes nothing the attack press test 0x0C09E71C -> the selector 0x0C09E4AC, which walks the fighter's command table
## (0x0C338E4C[char], 16-byte entries, b0 0 = a string start, +4 the button) and takes the FIRST start entry whose button
## was pressed: with both bits that is entry 0 = punch for everyone but Rouge (her entry 0 is the kick). Logged: B / X+Y
## / B+X / B+Y from idle or a run = k1/16 for Falcon, Ryoma, Jack, Gunrock, Galuda, Kraken, Ayame (27 of 27), k1/24 for
## Rouge (5 of 5). Air: the air list (poles ...) first, then the selector's air branch: punch pressed = the air punch.
func _mv_act() -> bool:
	return ic.is_pressed("action") or (ic.is_pressed("punch") and ic.is_held("kick")) \
		or (ic.is_pressed("kick") and ic.is_held("punch"))

func _mv_first_btn() -> String:   # the button the selector takes with these presses ("" = none)
	var p := ic.is_pressed("punch") or ic.is_pressed("action")
	var k := ic.is_pressed("kick") or ic.is_pressed("action")
	if p and k: return "Y" if char_id == "rouge" else "X"
	return "X" if p else ("Y" if k else "")

## ground: the attack the selector picks (the same path as a plain punch / kick press in _core_actions)
func _mv_action_attack() -> bool:
	var b := _mv_first_btn()
	if b == "": return false
	if powered:
		if _pc_attack(b): return true
		if Rules.can_drive(gauge): _start_attack("drive_p" if b == "X" else "drive_k")
		else: _start_attack("punch1" if b == "X" else "kick1")
		return true
	if _core_obj_punch(b): return true
	var cat := b
	if gst == 31: cat = "R" + cat
	elif _opp_near(): cat += "_near"
	if _core_attack(cat): return true
	_start_attack("punch1" if b == "X" else "kick1")
	return true

## air: nothing in the air list caught -> the dive (0x0C09E470, below) when it applies, else the air attack (the
## selector's air branch: punch pressed = 0, so B = AX)
func _mv_air_action() -> bool:
	if _mv_hang41(): return true
	if air_attacked: return false
	air_attacked = true
	if not powered and _mv_dive_start(): return true
	if powered and _pc_attack("AX"): return true
	if not powered and _core_attack("AX"): return true
	vel_to_legacy()
	_start_attack("air")
	return true

## The fx-mv machine: one of its states owns the fighter while mv_k is set and gst / state are still the ones it set
## (anything else that takes the fighter over - a hit, a throw, the round flow - drops it).
var mv_k := ""          # "" | "dive" | "turn" | "vault" | "hang"
var mv_t := 0           # rows since the state started (0 = its first row, already moved by the state before)
var mv_i := 0           # sub-step
var mv_n := 0
var mv_j := 0
var mv_v := Vector3.ZERO
var _mv_g := -1
var _mv_s := -1

func _mv_live() -> bool:
	if mv_k == "": return false
	if gst != _mv_g or state != _mv_s or rx_on or thr_on or held_by or state == S.POLE:
		mv_k = ""
		return false
	return true

func _mv_begin(k: String, g: int, coarse: int) -> void:
	_core_setting = true
	if state != coarse:
		state = coarse; state_t = 0.0
	_core_setting = false
	gst = g; gst_t = 0
	mv_k = k; mv_t = 0; mv_i = 0; mv_n = 0
	_mv_g = g; _mv_s = state
	if model is PSModel: (model as PSModel).root_motion = false

## Hook (top of _core_tick): true = an fx-mv state ran this frame
func _mv_tick(dt: float) -> bool:
	_mv_pre = global_position
	_mv_pad()
	if not _mv_live(): return false
	state_t += dt
	invuln = maxf(0.0, invuln - dt)
	gst_t += 1; mv_t += 1
	reach_obj = _reach_prop()
	match mv_k:
		"dive": _mv_dive_tick()
		"arc": _mv_arc_tick()
		"step": _mv_step_tick()
		"hop": _mv_hop_tick()
		"hang41": _mv_hang41_tick()
		"hang36": _mv_hang36_tick()
	_apply_facing()
	return true

## BUG-27 / BUG-53 air: the air ACTION list's last entry 0x0C09E470 = at least 150 cm of air below the feet and the
## opponent not airborne -> state 10 kind 4, k1/53 (shared init 0x0C06384A: horizontal 0, vy0, gravity 2.8), then
## k1/54 straight down until the floor, then the landing motions. Per fighter, measured on the 48 disc CPU logs +
## the mash tapes (66 dives): [k1/53 rows, vy0, gravity through k1/53, k1/54 speed from its 2nd row, its growth per
## row, landing chain [k1 motion, rows]]. The first k1/53 row keeps the jump's own move; the first k1/54 row still
## follows the k1/53 arc; the landing chain starts the frame after the floor is reached. Wang-Tang lands with the
## normal state 6 (k0/9). A dive that connects bounces off the victim on the disc (k1/55 > k1/56 > k1/10): not ported.
const MV_DIVE := {
	"falcon": [14, 20.0, 2.8, -15.0, 1.0, [[146, 18]]], "rouge": [14, 20.0, 2.8, -15.0, 1.0, [[146, 31]]],
	"ayame": [14, 20.0, 2.8, -15.0, 1.0, [[146, 25]]], "ryoma": [14, 20.0, 2.8, -25.0, 1.0, [[56, 16]]],
	"kraken": [10, 20.0, 2.8, -15.0, 1.0, [[146, 18]]], "galuda": [10, 40.0, 2.8, -20.0, 1.0, [[56, 27], [146, 31]]],
	"valgas": [10, 40.0, 2.8, -20.0, 1.0, [[56, 27], [147, 23]]], "gunrock": [10, 40.0, 2.8, -20.0, 1.0, [[56, 27], [147, 23]]],
	"wangtang": [10, 0.0, 0.0, -8.0, 1.5, []], "jack": [14, 0.0, 0.0, -10.0, 1.0, [[56, 16]]],
}
const MV_DIVE_AIR_CM := 150.0
var _mv_dive: Array = []

func _mv_has(kind: int, mot: int) -> bool:
	if not (model is PSModel): return false
	var pm := model as PSModel
	return (pm.players.get(pm.form) as AnimationPlayer).has_animation("%sk%d_%03d" % [_clip_prefix(), kind, mot])

func _mv_dive_start() -> bool:
	if boss or carry or not MV_DIVE.has(char_id) or not _mv_has(1, 53): return false
	if opponent and not opponent.grounded(): return false
	if (global_position.y - _floor_under()) * 100.0 < MV_DIVE_AIR_CM: return false
	_mv_dive = MV_DIVE[char_id]
	cur_attack = "air"; attack_hit = false; _hit_mark = ""; hit_stop = 0
	_mv_begin("dive", 10, S.JUMP)
	_gplay(1, 53)
	return true

func _mv_dive_tick() -> void:
	var t: Array = _mv_dive
	if model is PSModel: (model as PSModel).time_scale = 0.0 if hit_stop > 0 else 1.0
	if hit_stop > 0:
		hit_stop -= 1; mv_t -= 1
		return
	var n53: int = t[0]
	match mv_i:
		0:   # k1/53: hang in the air on its own small arc, no horizontal move
			if mv_t >= n53:
				mv_i = 1; mv_n = 0
				_gplay(1, 54)
				vcm = Vector3(0, float(t[1]) - float(t[2]) * (n53 - 1), 0)
			else:
				vcm = Vector3(0, float(t[1]) - float(t[2]) * (mv_t - 1), 0)
		1:   # k1/54: straight down, faster every row, until the floor
			mv_n += 1
			vcm = Vector3(0, float(t[3]) - float(t[4]) * (mv_n - 1), 0)
		2:   # the landing chain, from the frame after the floor was reached
			vcm = Vector3.ZERO
			mv_n += 1
			var ch: Array = t[5]
			if mv_n == 0: _gplay(1, int(ch[mv_j][0]))
			elif mv_n >= int(ch[mv_j][1]):
				mv_j += 1; mv_n = 0
				if mv_j >= ch.size():
					mv_k = ""
					air_attacked = false; wk_used = false
					_gset(0, S.IDLE)
					return
				_gplay(1, int(ch[mv_j][0]))
			_core_move(Vector3.ZERO, true)
			return
	_core_move(vcm, false)
	var before: int = int(stats.hits)
	_game_hit_update()
	if stats.hits > before: hit_stop = _rx_stop if _rx_stop >= 0 else HITSTOP_ATK
	if mv_i == 1 and grounded():   # the floor is reached
		if (t[5] as Array).is_empty():
			mv_k = ""
			air_attacked = false; wk_used = false
			_gset(6, S.IDLE); gst = 6
			return
		mv_i = 2; mv_n = -1; mv_j = 0

## --- stage geometry read off the disc (game/assets/fidelity/mv_stage.json, docs/fx-mv.md 3): pole cylinders, the
## push-out radii, the state-41 kind-4 objects, the class-9 undersides of state 36, the hoppable boxes, body heights
static var _mvd := {}
static func _mv_data() -> Dictionary:
	if _mvd.is_empty() and FileAccess.file_exists("res://assets/fidelity/mv_stage.json"):
		_mvd = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/mv_stage.json"))
	return _mvd

func _mv_stage_list(key: String) -> Array:
	if not arena: return []
	return (_mv_data().get(key, {}) as Dictionary).get(str(arena.get("stage")), []) as Array

func _mv_body_h() -> float:   # cm (0x0C02651E: what the pole / hang inits subtract)
	return float((_mv_data().get("body_height_cm", {}) as Dictionary).get(char_id, 200.0))

func _feet_cm() -> Vector3: return global_position * 100.0

## Every core frame, after the state's move (hook in _core_tick): the pole bump and the hop boxes' contact
var _mv_pre := Vector3.ZERO       # the feet before this frame's move
var _mv_touch: Array = []         # the hoppable box touched this frame (run): a _mv_hop_list entry
var _mv_touch_last: Array = []    # the previous frame's (the disc tests the contact list of the frame before)
func _mv_after_move() -> void:
	_mv_pole_push()
	_mv_ceiling()
	_mv_touch_last = _mv_touch
	_mv_touch = _mv_box_contact()

## BUG-50 the pole catch (decode: the touch scan 0x0C0ABF64 + 0x0C09FE68, docs/fx-mv.md 4): the nearest pole by
## horizontal feet-to-axis distance under 150 cm while airborne whose cylinder overlaps the body window (feet + 100 >
## its bottom, its top > head - 100); no facing or approach test. The init (0x0C0A0370) clamps the feet into the pole:
## below its bottom -> the bottom, the head over its top -> top - body height (mash_s33 Ayame: 550 - 180 = 370). The 10
## moving jumps of pole_londo / pole_londo2 / pole_wall press no ACTION within 150 cm: 0 catches on the disc.
const MV_POLE_REACH_AIR := 150.0
func _mv_pole_catch():   # -> the pole axis (metres, y 0) or null; sets the clamped feet height
	var list := _mv_stage_list("poles")
	if list.is_empty():   # no table for this stage: the arena's own poles
		return arena.nearest_pole(global_position, MV_POLE_REACH_AIR * 0.01) if arena and arena.has_method("nearest_pole") else null
	var f := _feet_cm()
	var h := _mv_body_h()
	var best: Array = []
	var bd := MV_POLE_REACH_AIR
	for q in list:
		var d := Vector2(float(q[0]) - f.x, float(q[1]) - f.z).length()
		if d >= bd or not (f.y + 100.0 > float(q[2]) and float(q[3]) > f.y + h - 100.0): continue
		bd = d; best = q
	if best.is_empty(): return null
	var y := f.y
	if y < float(best[2]): y = float(best[2])
	elif y + h > float(best[3]): y = float(best[3]) - h
	global_position.y = y * 0.01   # the init's clamp (the lead's snap keeps y)
	return Vector3(float(best[0]), 0, float(best[1])) * 0.01

## The bump: the pole's cylinder (radius 20) holds the feet out at radius + the fighter's collision radius (push_out_cm,
## exact on the tape logs: Ryoma 60, Falcon 50, Kraken 72 ...); the velocity is kept, so a jump straight at the post
## drops down beside it (pole_londo f18-51: 60.0 cm from the axis every row, vx / vz -6.89 kept).
func _mv_pole_push() -> void:
	var list := _mv_stage_list("poles")
	if list.is_empty(): return
	var f := _feet_cm()
	var h := _mv_body_h()
	var r := float((_mv_data().get("push_out_cm", {}) as Dictionary).get(char_id, 20.0 + body_radius(char_id) * 100.0))
	for q in list:
		if f.y >= float(q[3]) or f.y + h <= float(q[2]): continue
		var dv := Vector2(f.x - float(q[0]), f.z - float(q[1]))
		var d := dv.length()
		if d >= r: continue
		var n := dv / d if d > 0.01 else Vector2(-facing.x, -facing.z).normalized()
		# out round the pole, never into the void beside it: a pole at the area's edge (Ryoma's stage (-440, 190), a
		# 20 cm floor patch) pushed a Power Change Wang-Tang 35 cm out over no floor (BUG-105); the nearest way round
		# whose spot is inside the area (the disc's floor / wall clamp keeps every body in), else straight out + clamp
		if arena and arena.has_method("fighter_margin"):
			var m: float = arena.fighter_margin(char_id)
			var air := not grounded()
			for k in 25:
				var a := deg_to_rad(15.0 * ((k + 1) / 2) * (1 if k % 2 == 1 else -1))
				var nk := n.rotated(a)
				var x := (float(q[0]) + nk.x * r) * 0.01; var z := (float(q[1]) + nk.y * r) * 0.01
				if (arena.air_sdf_at(x, z) if air else arena.sdf_at(x, z)) >= m: n = nk; break
		global_position.x = (float(q[0]) + n.x * r) * 0.01
		global_position.z = (float(q[1]) + n.y * r) * 0.01
		if arena and arena.has_method("clamp_fighter"): arena.clamp_fighter(self)

## BUG-58 = the DODGE, state 7 (decode: trigger 0x0C09E910 in the handlers of states 0 / 2 / 31 / 32 after the attack
## tests, init 0x0C09F6A8, handler 0x0C094562; 16 of 16 logged entries): not carrying, the opponent on the floor in an
## attack (state 10 / 11) early (frame <= 15) with a hit armed (+0x100), |dy| <= 100, distance D <= 300, and a newly
## pressed stick direction: d = the stick (8-way + camera) - the heading to him. |d| <= 20 deg = state 28 (toward him,
## not decoded: the normal move goes on); 20..100 deg = the ARC k0/41: 20 moves of L = 2 sin(2 deg) D (D frozen at the
## trigger) along heading(him) +- 90 deg, facing him every frame (a circle round him), 21 rows; over 100 deg = the STEP
## k0/20..23 (by the octant of the step against him: toward 20, away 21, sides 22 / 23): 32 cm/f along the stick, -2
## per frame, 12 moves, 13 rows. Then the disc's neutral: stick held = walk start (state 2) and the run, else idle. No
## button is read during either; no hit registers on the first 11 frames (+0x106). The jump-dodge (state 5 sub 4,
## jump pressed in the same window) is not decoded: the normal jump goes on.
const MV_DODGE_D := 300.0
const MV_ARC_K := 0.069799
const MV_STEP_MOT := [20, 23, 23, 23, 21, 22, 22, 22]
var _mv_dirs := 0
var _mv_dirs_f := -10
var _mv_fresh := false
var _mv_fresh_last := false       # the previous frame's fresh press (its stick in _mv_move_last)
var _mv_move_last := Vector2.ZERO
var _mv_side := 0.0
var _mv_stick := Vector2.ZERO
var _mv_dir := 0.0

func _mv_pad() -> void:   # the stick's newly pressed directions this frame (the pad's +0x2E4 & 0xF0)
	var m := ic.move
	var b := 0
	if m.length() > 0.22:
		var n := m.normalized()
		if n.y < -0.38: b |= 0x10
		if n.y > 0.38: b |= 0x20
		if n.x < -0.38: b |= 0x40
		if n.x > 0.38: b |= 0x80
	var now := Engine.get_physics_frames()
	_mv_fresh_last = _mv_fresh and _mv_dirs_f == now - 1
	if _mv_fresh: _mv_move_last = _mv_stick
	_mv_fresh = (b & ~_mv_dirs) != 0 and _mv_dirs_f == now - 1
	_mv_stick = m
	_mv_dirs = b; _mv_dirs_f = now

func _mv_opp_attack_early() -> bool:
	var o := opponent
	if o == null or not (o.gst in [10, 11]): return false
	var mf: int = o.gmo_f if o.core_atk else (o.pc_fr if o.pc_on else o.gst_t)
	if mf > 15: return false
	if o.ghits and o.ghits.ok:
		var mo := o._motion()
		if o.ghits.has_move(mo[0]) and int(o.ghits.at(mo[0], mo[1]).hit) == 0: return false
	return true

func _mv_dodge() -> bool:
	if carry or boss or opponent == null or not opponent.grounded() or not (model is PSModel): return false
	var m := ic.move
	if not _mv_fresh:
		# the disc's own update order lets a press see an attack that starts on the same frame (mash_s22 f12: P2's k1/74
		# and P1's dodge on one row); here the opponent ticks after this fighter, so a press on the frame his attack
		# started is taken one frame late
		if not (_mv_fresh_last and opponent.pid > pid and opponent.gst in [10, 11] and opponent.gst_t == 0): return false
		m = _mv_move_last
	var dv := (opponent.global_position - global_position) * 100.0
	if absf(dv.y) > 100.0: return false
	var dist := Vector2(dv.x, dv.z).length()
	if dist > MV_DODGE_D or not _mv_opp_attack_early(): return false
	var h_opp := _ang(Vector3(dv.x, 0, dv.z))
	var q := roundf(atan2(m.x, m.y) / (PI / 4.0)) * (PI / 4.0)
	var sv := cam_basis * Vector3(sin(q), 0, cos(q)); sv.y = 0
	var stick := _ang(sv)
	var d := _wrap(stick - h_opp)
	if absf(d) <= (deg_to_rad(20.0) if opponent.gst != 11 else 0.0): return false
	if absf(d) <= deg_to_rad(100.0):
		if not _mv_has(0, 41): return false
		_mv_side = PI * 0.5 if d > 0.0 else -PI * 0.5
		mv_v = Vector3(MV_ARC_K * dist, 0, 0)
		_mv_begin("arc", 7, S.RUN)
		_gplay(0, 41)
	else:
		var oc := int(floor(wrapf(h_opp - stick + PI / 8.0, 0.0, TAU) / (PI / 4.0))) % 8
		var mot: int = MV_STEP_MOT[oc]
		if not _mv_has(0, mot): return false
		_mv_dir = stick
		_mv_begin("step", 7, S.RUN)
		_gplay(0, mot)
	facing = _dir(h_opp); head = h_opp
	global_position.x = _mv_pre.x; global_position.z = _mv_pre.z   # tested before the state's move (mash_s11 f46)
	invuln = maxf(invuln, 10.5 / 60.0)
	vcm = Vector3.ZERO
	return true

func _mv_face_opp() -> void:
	if opponent == null: return
	var d := opponent.global_position - global_position; d.y = 0
	if d.length() > 0.001: facing = d.normalized(); head = _ang(facing)

func _mv_end() -> void:   # the disc's neutral(): airborne = fall, stick held = walk start (state 2), else idle
	mv_k = ""
	if not grounded():
		_gset(14, S.JUMP); return
	var mv := _move_dir()
	if mv.length() > 0.1:
		facing = mv.normalized(); head = _ang(facing)
		_gset(2, S.RUN)
	else:
		_gset(0, S.IDLE)

func _mv_arc_tick() -> void:
	if mv_t > 20:
		_mv_end(); return
	_mv_face_opp()
	var tg := _dir(head + _mv_side) * mv_v.x
	var on_f := grounded()
	vcm = Vector3(tg.x, 0.0 if on_f else vcm.y - GRAV_CM, tg.z)
	_core_move(vcm, on_f)
	_mv_after_move()

func _mv_step_tick() -> void:
	if mv_t > 12:
		_mv_end(); return
	_mv_face_opp()
	var dv := _dir(_mv_dir) * (32.0 - 2.0 * (mv_t - 1))
	var on_f := grounded()
	vcm = Vector3(dv.x, 0.0 if on_f else vcm.y - GRAV_CM, dv.z)
	_core_move(vcm, on_f)
	_mv_after_move()

## BUG-48 = the HOP onto a box, state 17 (decode: trigger 0x0C0A1162 in the run handler, init 0x0C0A11F4, handler
## 0x0C0953BA; 46 of 46 entries from the run): running, touching a hoppable box (kind 1, its stage descriptor's hop byte
## [11]: mv_stage.json "hop") whose base is within 8 cm of the feet and whose centre lies within 40 deg of the run, on 5
## frames running (the box halves the run's step into it meanwhile: stg_10 f704-708 -4.46 of -8.93 cm/f). k0/48 at
## 1 cm/f (6 rows, Jack 11); k0/57: the feet onto the box top and 50 cm toward its centre, 12 cm/f (the stick steers
## after 6 frames; jump = state 4; stick released = stand on it); off the box: 100 cm down at once, k0/58 8 rows at
## 8.33 cm/f (Jack 0), then the run (k0/24, Jack k0/25) if the stick was held, else neutral. Placement 17 of 18 logged
## hops within 0.1 cm. The box: shape set 1 = 100 cm cube; side contact fitted on stg_10 (feet 20 cm off its face).
const MV_BOX_HALF := 50.0
## contact with the box = the fighter's collision radius - 10 cm from its face (fitted: stg_10 Falcon (30) 20 cm, stg_30
## Galuda (48) 38 cm), on top = radius + 10 (stg_10 Falcon kept at 32.1 cm, off at 43.4)
func _mv_box_touch() -> float: return body_radius(char_id) * 100.0 - 10.0
func _mv_box_on() -> float: return body_radius(char_id) * 100.0 + 10.0
const MV_HOP_DOWN := [8.33, 8.33, 8.33, 8.33, 8.33, 8.33, 5.0]   # k0/58 rows 1..7 (its root motion, logged)
var _mv_hop_n := 5
var _mv_box: Node3D = null        # the box as a prop (null = scenery)
var _mv_box_t := Transform3D.IDENTITY
var _mv_box_top := 0.0
var _mv_hop_ee := 0
var _mv_hop_stick := false

## [[prop or null, top cm, bottom cm, the box's transform], ...]: the hoppable boxes at rest. Boxes the remaster keeps
## as scenery (not throwable props here, e.g. stg10 part 11) stand at their logged home, axis-aligned.
func _mv_hop_list() -> Array:
	var out := []
	if not arena: return out
	var tab: Dictionary = (_mv_data().get("hop", {}) as Dictionary).get(str(arena.get("stage")), {})
	if tab.is_empty(): return out
	var seen := {}
	for p in arena.props:
		if not (p is Prop): continue
		var e = tab.get(str((p as Prop).part))
		if e == null: continue
		seen[str((p as Prop).part)] = true
		if (p as Prop).state != Prop.REST: continue
		var dy := (p as Prop).global_position.y * 100.0 - (p as Prop).home.y * 100.0
		out.append([p, float(e[0]) + dy, float(e[1]) + dy, (p as Node3D).global_transform])
	for k in tab:
		if seen.has(k): continue
		var e: Array = tab[k]
		out.append([null, float(e[0]), float(e[1]), Transform3D(Basis.IDENTITY, Vector3(float(e[2]), float(e[3]), float(e[4])) * 0.01)])
	return out

static func _mv_box_local(t: Transform3D, w: Vector3) -> Vector3: return t.affine_inverse() * w

static func _mv_box_edge(l: Vector3) -> float:   # cm from the box's footprint (0 inside)
	return Vector2(maxf(absf(l.x) * 100.0 - MV_BOX_HALF, 0.0), maxf(absf(l.z) * 100.0 - MV_BOX_HALF, 0.0)).length()

func _mv_box_contact() -> Array:   # running: the box touched after this frame's move (the step into it halved)
	if gst != 31 or carry: return []
	var hit: Array = []
	var fy := _feet_cm().y
	for e in _mv_hop_list():
		var t: Transform3D = e[3]
		if absf(fy - float(e[2])) >= 8.0: continue
		var l1 := _mv_box_local(t, global_position)
		if _mv_box_edge(l1) >= _mv_box_touch(): continue
		var l0 := _mv_box_local(t, _mv_pre)
		var s := (MV_BOX_HALF + _mv_box_touch()) * 0.01
		var ax := 0 if absf(l0.x) - MV_BOX_HALF * 0.01 >= absf(l0.z) - MV_BOX_HALF * 0.01 else 2
		var a0 := l0[ax]; var a1 := l1[ax]
		var sg := signf(a0) if absf(a0) > 0.0001 else 1.0
		l1[ax] = (sg * s + (a1 - sg * s) * 0.5) if absf(a0) >= s else (a0 + (a1 - a0) * 0.5)
		var w := t * l1
		global_position.x = w.x; global_position.z = w.z
		if hit.is_empty(): hit = e
	return hit

func _mv_hop() -> bool:   # transitions of the run: 5 touching frames -> state 17
	if gst != 31 or carry or _mv_touch.is_empty() or _mv_touch_last.is_empty():
		_mv_hop_n = 5; return false
	var bt: Transform3D = _mv_touch[3]
	var to := bt.origin - global_position; to.y = 0
	var v := Vector3(vcm.x, 0, vcm.z)
	if v.length() < 0.01 or to.length() < 0.001 or v.normalized().dot(to.normalized()) <= 0.766:
		_mv_hop_n = 5; return false
	_mv_hop_n -= 1
	if _mv_hop_n > 0: return false
	_mv_hop_n = 5
	if not _mv_has(0, 48): return false
	_mv_box = _mv_touch[0]; _mv_box_t = bt; _mv_box_top = float(_mv_touch[1])
	global_position.x = _mv_pre.x; global_position.z = _mv_pre.z   # the disc tests before the run's move: no step
	head = _ang(v); facing = _dir(head)
	mv_v = _dir(head)
	_mv_begin("hop", 17, S.RUN)
	mv_n = 11 if char_id == "jack" else 6
	_gplay(0, 48)
	vcm = Vector3.ZERO
	return true

func _mv_on_box(r: float) -> bool:
	if _mv_box != null and (not is_instance_valid(_mv_box) or (_mv_box as Prop).state != Prop.REST): return false
	return _mv_box_edge(_mv_box_local(_mv_box_t, global_position)) < r

## feet on a hoppable box's top (state 17 / standing on it after; a prop the stage-only floor ray doesn't see):
## inside its footprint + the on-top reach, within 10 cm of its top (the out-of-map check's box floor)
func on_hop_box(above := 10.0) -> bool:   # above: cm over the top still counted (the out-of-map check: 40)
	var fy := global_position.y * 100.0
	for e in _mv_hop_list():
		if fy - float(e[1]) < -10.0 or fy - float(e[1]) > above: continue
		if _mv_box_edge(_mv_box_local(e[3], global_position)) < _mv_box_on(): return true
	return false

func _mv_hop_move(d: Vector3) -> void:   # cm, written straight like the disc (the handler sets the position)
	global_position += Vector3(d.x, 0, d.z) * 0.01
	if arena and mv_i != 1: arena.clamp_fighter(self)   # up on the box the area's floor-level clamp doesn't apply
	vcm = Vector3(d.x, 0, d.z)

func _mv_hop_tick() -> void:
	var mv := _move_dir()
	match mv_i:
		0:   # k0/48: pressing in at 1 cm/f until the clip's last row
			if mv_t < mv_n:
				_mv_hop_move(mv_v); return
			_gplay(0, 57); _mv_hop_ee = 6
			if _mv_on_box(_mv_box_on() + 20.0):
				var to := _mv_box_t.origin - global_position; to.y = 0
				if to.length() > 0.001: global_position += to.normalized() * 0.5
				global_position.y = _mv_box_top * 0.01
				mv_i = 1
				_mv_hop_move(mv_v)
			else:
				_mv_hop_drop()
		1:   # k0/57 on the box
			if ic.is_pressed("jump"):
				mv_k = ""; air_move = false; air_ctrl = false; air_attacked = false
				_gset(4, S.JUMP); return
			if _mv_hop_ee > 0: _mv_hop_ee -= 1
			if _mv_hop_ee == 0:
				if not _mv_on_box(_mv_box_on()):
					_mv_hop_drop(); return
				global_position.y = _mv_box_top * 0.01
			if mv.length() > 0.1 or _mv_hop_ee > 0:
				if mv.length() > 0.1 and _mv_hop_ee == 0: head = _ang(mv); facing = _dir(head)
				_mv_hop_move(_dir(head) * 12.0)
			else:   # stand on it (k0/1, then the core's idle)
				_mv_face_opp()
				mv_k = ""
				_gset(0, S.IDLE)
				_gplay(0, 1)
		2:   # k0/58 down off the box
			mv_n += 1
			if mv.length() > 0.1: _mv_hop_stick = true
			var stop := 8 if _mv_hop_stick else 13
			if mv_n >= stop:
				mv_k = ""
				if _mv_hop_stick:
					_land_run = 0 if char_id == "jack" else 8
					if mv.length() > 0.1: facing = mv.normalized()
					head = _ang(facing)
					_gset(31, S.RUN)
					if char_id == "jack": _gplay(0, 25)
				else: _mv_end()
				return
			var sp: float = 0.0 if char_id == "jack" else (MV_HOP_DOWN[mv_n - 1] if mv_n - 1 < MV_HOP_DOWN.size() else 0.0)
			_mv_hop_move(_dir(head) * sp)

func _mv_hop_drop() -> void:   # off the box: 100 cm down at once (the floor catches the feet), k0/58, no move this row
	_gplay(0, 58)
	var fl := _floor_under() if arena else global_position.y - 1.0
	global_position.y = maxf(global_position.y - 1.0, fl)
	mv_i = 2; mv_n = 0; _mv_hop_stick = _move_dir().length() > 0.1
	vcm = Vector3.ZERO

## State 41 (decode: trigger 0x0C0A01EC, init 0x0C0A0B78, handler 0x0C097864): the air ACTION edge with a kind-4 object
## (mv_stage.json "kind4") within 200 cm horizontally and 250 cm vertically, the nearest: x, z onto it, feet = its y -
## body height, k2/207, velocity 0, no input; 20 frames later the hop off: vy 18, gravity 1.5, 5 cm/f along the facing,
## k0/8, until the floor, then the landing (state 6 k0/9). Logged 3 of 3.
func _mv_hang41() -> bool:
	if carry or boss: return false
	var f := _feet_cm()
	var best: Array = []
	var bd := 200.0
	for o in _mv_stage_list("kind4"):
		var d := Vector2(float(o[0]) - f.x, float(o[2]) - f.z).length()
		if d < bd and absf(f.y - float(o[1])) < 250.0: bd = d; best = o
	if best.is_empty() or not _mv_has(2, 207): return false
	global_position = Vector3(float(best[0]), float(best[1]) - _mv_body_h(), float(best[2])) * 0.01
	_mv_begin("hang41", 41, S.JUMP)
	_gplay(2, 207)
	vcm = Vector3.ZERO
	return true

func _mv_hang41_tick() -> void:
	if mv_i == 0:
		vcm = Vector3.ZERO
		if mv_t < 20: return
		mv_i = 1
		_gplay(0, 8)
		var d := _dir(_ang(facing)) * 5.0
		vcm = Vector3(d.x, 18.0, d.z)
	else:
		vcm.y -= 1.5
	_core_move(vcm, false)
	_mv_after_move()
	if mv_i == 1 and vcm.y < 0.0 and grounded():
		mv_k = ""
		air_attacked = false; wk_used = false
		_gset(6, S.IDLE); gst = 6

## State 36 = the hang under a class-9 underside (decode: trigger 0x0C09FF0C, init 0x0C0A07E4, handler 0x0C09701A; 14
## logged): the stage boxes tagged class 9 (mv_stage.json "class9": eaves / ceilings, bottoms 550-700) stop a rising
## head (the feet pinned at bottom - body height while vy runs down: mash_s22 Wang-Tang f478-481 at 408.9 = 600 -
## 191.1); on the air ACTION edge with the head against one (or within 30 cm / 20 cm below where it touched this
## airtime): feet = bottom - body height + 3, velocity 0, k2/207 (20 f) then the hold (k2/208: not captured off the disc,
## k2/207's last pose holds). Punch / kick = the hang attack (state 10 kind 8, 0x0C064DB4): k1/162 in place (26 f,
## Gunrock 20), then k1/163 a straight dive at 25 cm/f at the opponent (D = min(distance, 200), pitch from up =
## atan((y - his y - 50) / D) + 90 deg, at least 140, i.e. 50 deg below level; no gravity) until the floor, then k1/171
## 22 f. Off the underside's span or on a floor = fall (state 5). No jump-off on the disc. Not ported: the k2/209
## hand-over-hand walk (not captured), the +132 cm bone snap on k1/163's first row, Rouge's fixed pitch.
var _mv_t9 := []                 # this airtime's touch: [feet y, x, z] cm
var _mv_hit36 := false
const MV_HANG_LIFT := {"wangtang": 131.89, "ayame": 133.97, "kraken": 175.05, "jack": 158.53, "ryoma": 149.66,
	"gunrock": 152.61, "galuda": 135.62}   # cm, k1/163's first row on the disc logs (Falcon / Rouge / Valgas not logged)
var _mv_box9: Array = []
func _mv_box9_at(f: Vector3) -> Array:
	for b in _mv_stage_list("class9"):
		if f.x > float(b[0]) and f.x < float(b[1]) and f.z > float(b[2]) and f.z < float(b[3]): return b
	return []

func _mv_ceiling() -> void:   # the class-9 undersides stop a rising head (the velocity runs on, as logged)
	if grounded() or mv_k == "hang36":
		_mv_t9 = [] if grounded() else _mv_t9
		return
	var f := _feet_cm()
	var b := _mv_box9_at(f)
	if b.is_empty(): return
	var h := _mv_body_h()
	var bot := float(b[4])
	if f.y + h > bot and f.y + h < bot + 60.0 and vcm.y >= 0.0:
		global_position.y = (bot - h) * 0.01
		_mv_t9 = [bot - h, f.x, f.z]

func _mv_hang36() -> bool:
	if carry or boss or grounded() or not _mv_has(2, 207): return false
	var f := _feet_cm()
	var b := _mv_box9_at(f)
	var h := _mv_body_h()
	var y := 0.0
	if not b.is_empty() and f.y + h >= float(b[4]) - 3.0 and f.y + h < float(b[4]) + 60.0:
		y = float(b[4]) - h + 3.0
	elif not _mv_t9.is_empty() and f.y > float(_mv_t9[0]) - 20.0 \
			and Vector2(f.x - float(_mv_t9[1]), f.z - float(_mv_t9[2])).length() <= 30.0:
		y = float(_mv_t9[0]) + 3.0
		b = _mv_box9_at(Vector3(float(_mv_t9[1]), 0, float(_mv_t9[2])))
	else:
		return false
	global_position.y = y * 0.01
	_mv_box9 = b
	_mv_begin("hang36", 36, S.JUMP)
	_gplay(2, 207)
	vcm = Vector3.ZERO
	_mv_t9 = []
	return true

func _mv_hang36_tick() -> void:
	match mv_i:
		0:   # hanging
			vcm = Vector3.ZERO
			if _mv_box9.is_empty() or _mv_box9_at(_feet_cm()).is_empty():
				mv_k = ""; air_move = false; air_ctrl = false
				_gset(5, S.JUMP); gst_t = 2
				return
			if ic.is_pressed("punch") or ic.is_pressed("kick"):
				mv_i = 1; mv_n = 0
				gst = 10; _mv_g = 10; gst_t = 0
				cur_attack = "air"; attack_hit = false; _hit_mark = ""; hit_stop = 0
				_mv_face_opp()
				_gplay(1, 162)
		1:   # k1/162 in place
			if hit_stop > 0:
				hit_stop -= 1; return
			mv_n += 1
			if mv_n >= (20 if char_id == "gunrock" else 26):
				mv_i = 2; mv_n = 0
				_mv_face_opp()
				var d := 0.01
				var dy := 0.0
				if opponent:
					var o := (opponent.global_position - global_position) * 100.0
					d = maxf(minf(Vector2(o.x, o.z).length(), 200.0), 0.01)
					dy = -o.y
				var pitch := maxf(atan((dy - 50.0) / d) + PI * 0.5, deg_to_rad(140.0))
				var hd := _dir(head) * sin(pitch) * 25.0
				mv_v = Vector3(hd.x, cos(pitch) * 25.0, hd.z)
				_gplay(1, 163)
				# the feet go to a model bone on k1/163's first row (the disc's lift, logged per fighter)
				global_position.y += float(MV_HANG_LIFT.get(char_id, 140.0)) * 0.01
				_mv_hit36 = false
			else:
				_mv_hit_tick()
		2:   # k1/163 the dive
			if hit_stop > 0:
				hit_stop -= 1
				if hit_stop == 0 and _mv_hit36:   # connected: k1/170 bounces back off him
					mv_i = 4; mv_n = 0
					_gplay(1, 170)
					var bk := -Vector3(mv_v.x, 0, mv_v.z).normalized() * 5.0
					mv_v = Vector3(bk.x, 15.0 + 1.2, bk.z)
				return
			vcm = mv_v
			_core_move(vcm, false)
			_mv_after_move()
			var before: int = int(stats.hits)
			_mv_hit_tick()
			if stats.hits > before: _mv_hit36 = true
			elif grounded():
				mv_i = 3; mv_n = -1
		4:   # k1/170: 15 cm/f up, -1.2 per row, 5 cm/f back, until the floor, then the landing (state 6)
			mv_v.y -= 1.2
			vcm = mv_v
			_core_move(vcm, false)
			_mv_after_move()
			if vcm.y < 0.0 and grounded():
				mv_k = ""; air_attacked = false; wk_used = false
				_gset(6, S.IDLE); gst = 6
		3:   # k1/171 landing
			vcm = Vector3.ZERO
			mv_n += 1
			if mv_n == 0: _gplay(1, 171)
			elif mv_n >= 22:
				mv_k = ""; air_attacked = false; wk_used = false
				_gset(0, S.IDLE)

func _mv_hit_tick() -> void:
	var before: int = int(stats.hits)
	_game_hit_update()
	if stats.hits > before: hit_stop = _rx_stop if _rx_stop >= 0 else HITSTOP_ATK


## --- PC shots (fx-shot; docs/SHOTS.md): the Drive / Fusion shots (the original's type-1 pool objects) replayed by
## PCShots from game/assets/fidelity/pc_shots.json; a hit = the shot's spheres meeting the victim's body spheres.
var shots: PCShots = null

func _shots() -> PCShots:
	if shots == null: shots = PCShots.new(self)
	return shots

## the move's turn toward the opponent (PCShots.turn, logged per fighter and move: most ground Drives / Fusions face
## him on their first motion row; Ryoma's Drive X turns 1820 a row for 4 rows, Kraken's X / Y / Fusion Y 1225 / 142 /
## 1495 for 7-9; Falcon's X and Fusion Y, Gunrock's Fusion Y keep the heading; the air Drives keep it). The travel rows
## follow the new heading (pc_ref), as the disc's move travel follows the model heading.
func _shot_turn() -> void:
	var tr := PCShots.turn(char_id, pc_name)
	if tr.is_empty() or int(tr.get("n", 0)) <= 0: return
	var r0 := int(tr.row)
	if pc_i < r0 or pc_i >= r0 + int(tr.n): return
	var t := _shot_target()
	if t == null: return
	var d := t.global_position - global_position; d.y = 0
	if d.length() < 0.05: return
	var want := _ang(d)
	if bool(tr.get("snap", false)) and pc_i == r0:
		facing = d.normalized()
	elif not bool(tr.get("snap", false)) and r0 <= 2:   # a start turn (later rate rows are the motion's own spins)
		var cur := _ang(facing)
		var step := float(tr.rate) / ANG16 * TAU
		facing = _dir(cur + clampf(_wrap(want - cur), -step, step))
	else:
		return
	pc_ref = _ang(facing)
	_apply_facing()

## the moves whose code spins the model (pc_shots.py spins, game/assets/fidelity/pc_spin.json: Falcon's Drive Y / air Y,
## Ayame's, Jack's Fusion X): the logged heading change of this row; the joints and hit spheres turn with it, the travel
## (pc_ref) does not (the disc's body stays put)
static var _spin := {}
func _pc_spin() -> void:
	if _spin.is_empty():
		_spin = {"fighters": {}}
		if FileAccess.file_exists("res://assets/fidelity/pc_spin.json"):
			_spin = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/pc_spin.json"))
	var m: Dictionary = ((_spin.get("fighters", {}) as Dictionary).get(char_id, {}) as Dictionary).get(pc_name, {})
	if m.is_empty(): return
	var i := pc_i - int(m.row0)
	var d: Array = m.d
	if i < 0 or i >= d.size() or int(d[i]) == 0: return
	facing = _dir(_ang(facing) + float(d[i]) / ANG16 * TAU)
	_apply_facing()

func _shot_target() -> Fighter:
	var t: Fighter = opponent
	if enemies.size() > 0:
		var best := INF
		for o in enemies:
			var e: Fighter = o
			if e and e.global_position.distance_to(global_position) < best:
				best = e.global_position.distance_to(global_position); t = e
	return t

## my shot hit target: the record of my character by the shot's hit id (0x0C338A98[char] + id * 20), the game's damage
## (rec[1], type rec[4], the combo cut counts: Ryoma's Fusion X logged 14 x5 then 7 3 1); the reaction's direction is
## the shot's heading (+0x72A8 = object +0x30) unless rec[14] >= 32 (then from the shot, 0x0C08D662)
func shot_land(target: Fighter, hid: int, at: Vector3, heading: float) -> bool:
	var rb := _rx_record(self, hid)
	if rb.size() != 20 or not target.can_be_hit() or target._shot_this_frame(): return false
	var dmg := _hit_damage(target, {"dmg": int(rb[1]), "type": int(rb[4])}, int(rb[1]))
	var from := at if int(rb[14]) >= 32 else target.global_position - _dir(heading)
	if not target.shot_hit(dmg, self, hid, from): return false
	if not target.boss: combo_hits = mini(combo_hits + 1, 99)
	stats.hits += 1; stats.dmg_dealt += dmg
	return true

## a shot's hit on me: the damage on the frame the spheres meet, the reaction from my next frame (the original runs
## the pool's objects after the players: logged, the hit frame shows the damage with the victim untouched, the launch
## starts on the next one); one shot per frame (Ryoma's Drive Y: two pillars overlap him at t30, the second hits at t31),
## shots on consecutive frames all land (Ayame's Fusion X: 76, 77, 78).
## Otherwise a body hit's rules: the record's hit-stop, its gem drop (rec[16]), facing the hit.
var _shot_rx: Array = []

func _shot_this_frame() -> bool:
	return _shot_rx.size() == 4 and int(_shot_rx[3]) == Engine.get_physics_frames()

func shot_hit(dmg: int, attacker: Fighter, hid: int, from: Vector3) -> bool:
	if not can_be_hit() or _shot_this_frame(): return false
	if _shot_rx.size() == 4: _shot_react()   # last frame's hit: its reaction has begun on the disc before this one
	# (Ayame's Fusion X petals hit on 3 frames in a row: 76, 77, 78)
	if not can_be_hit(): return false
	if attacker: last_hit_by = attacker
	var hp0 := hp
	hp = Rules.apply_damage(hp, dmg)
	# an effect object's hit: a Power Change move's (type 3) or an object's (5): nothing to recover (HEALTH.md)
	_recover_hit(float(dmg), 3 if attacker and attacker.powered else 5, attacker, hp0)
	if powered and not boss:
		pc_g = maxi(0, pc_g - int(dmg / 240.0 * 5520.0)); _pc_sync()
	damaged.emit(self, dmg)
	fx.emit("hit", global_position + Vector3.UP * 1.1)
	if boss:
		if hp <= 0:
			set_state(S.DOWN); knocked_out.emit(self)
		return true
	_shot_rx = [attacker, hid, from, Engine.get_physics_frames()]
	return true

func _shot_react() -> void:
	var attacker: Fighter = _shot_rx[0]; var hid: int = _shot_rx[1]; var from: Vector3 = _shot_rx[2]
	_shot_rx = []
	if carry: _drop_carry(true)
	if arena and arena.drop_f >= 0:
		var n := _spill_n(attacker, hid)
		if n > 0:
			gems -= n; gem_count_changed.emit(self)
			arena.spill_from(self, (attacker.global_position if attacker else from) - global_position, n)
	var dir := global_position - from; dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else -facing
	facing = -dir
	if CORE and react_start(attacker, hid, from):
		hitstop = 0.0
		if hp <= 0: knocked_out.emit(self)
		return
	if CORE and rx_on:   # lying (class 13, not decoded): the damage only, the reaction runs on
		if hp <= 0: knocked_out.emit(self)
		return
	velocity = dir * 4.0 + (Vector3.UP * 6.0 if hp <= 0 else Vector3.ZERO)
	set_state(S.DOWN if hp <= 0 else S.HITSTUN)
	if hp <= 0: knocked_out.emit(self)


## --- fx-flow round-flow hooks --- (lane pstrailer2, fx-flow; docs/FLOW.md). The original's round poses by motion
## kind/id, set by fight.gd's round flow only: intro k3/0 (state 22), win k3/2|3 and TIME poses k3/5|6 (state 21), the
## KO'd fighter lying k2/144 (state 8), idle k0/0 (state 0). A motion not captured off the disc (k3/6) leaves the current
## one playing (never a stand-in).
func flow_pose(kind: int, mot: int, g: int) -> void:
	velocity = Vector3.ZERO; vcm = Vector3.ZERO
	rx_on = false; core_atk = false; hit_stop = 0   # the round flow owns the fighter from here (reaction / throw over)
	if thr_on and thr_victim and is_instance_valid(thr_victim) and thr_victim.held_by == self: thr_victim.held_by = null
	thr_on = false; held_by = null
	if g == 0: _gset(0, S.IDLE)
	else:
		_gset(g, S.KO if g == 8 else S.WIN)
		gst = g
		var named := false
		if model is PSModel:
			var pm := model as PSModel
			pm.root_motion = false
			var c := "%sk%d_%03d" % [pm.clip_for("idle").substr(0, 2), kind, mot]
			for n in ["intro", "ready", "win", "win2", "lose", "lying"]:   # the clipmap's own names first
				if not named and pm.has_clip(n) and pm.clip_for(n) == c: pm.play(n); named = true
		if not named: _gplay(kind, mot)
	if model is PSModel:   # the original never blends: the pose is on from this frame (no cross-fade, no empty Start node)
		var pm := model as PSModel
		var tr: AnimationTree = pm.trees.get(pm.form)
		var want := pm.clip_for(pm.playing)
		if tr and tr.is_inside_tree() and want != "" and pm.current_clip() != want:
			(tr.get("parameters/playback") as AnimationNodeStateMachinePlayback).start(want, true); tr.advance(0.0)

## ---------------------------------------------------------------------------------------------------------------
## Fidelity core (lane pstrailer2): the original's own frame logic, measured with same-input tapes against the disc in
## Flycast (docs/FIDELITY.md, tools/reflog.py + game/tests/tapes). Units are the game's: cm, cm/frame, one call per
## 1/60 s frame. Covers idle / run / stop / jumps / falls / landings; attacks, hits, throws, items, poles and the
## Power Change still run the remaster's code above (S.ATTACK ...) until they are ported the same way.
## Order inside a frame is the original's: the state's handler sets the velocity and moves, then the transitions run
## (a transition logs velocity 0 on its own frame, the new state's handler moves from the next frame).
const CORE := true
const CM_S := 0.6                 # cm/frame -> m/s
const RUN_CM := 9.5               # state 31 run (k0/25), from its first moving frame
const RUN_TURN := PI / 9.0        # run heading turns 20 deg/frame toward the stick; under 20 deg it halves the gap
const STOP_LEN := 23              # state 32 stop (k0/26): speed 9.5 * (7 - k) / 6 for k = 1..6, idle after 23 frames
const START_CM := 4.0             # state 2 > run start motion k0/24 after a landing, 8 frames at 4 cm/frame
const CROUCH_F := 3               # state 4 (k0/5) before a standing jump
const JUMP_VY := 35.5             # first rising frame (it moves 3 cm less: logged 0 > 32.5 > 66 > 97.5)
const GRAV_CM := 2.0              # cm/frame^2, every airborne state
const AIR_CM := 10.5              # standing jump: a direction in the air sets 10.5 cm/frame that way (facing stays)
const MJUMP_CM := 9.75            # moving jump (k0/10): 9.75 cm/frame along the run, 9.25 with the stick against it
const LAND_F := 4                 # state 6 (k0/9)
const STEP_UP_CM := 60.0          # a run snaps up onto floors up to here (Londo's 55 cm fountain base, one frame)
var gst := 0                      # the game's state id (0 idle, 2 start, 4 crouch, 5 air, 6 land, 14 fall, 31 run, 32 stop ...)
var gst_t := 0                    # frames since gst was set (0 on the frame it changes)
var vcm := Vector3.ZERO           # velocity, cm/frame
var head := 0.0                   # run velocity heading (game angle: 0 = +z, PI/2 = +x)
var air_move := false             # this jump left from a run (k0/10)
var air_ctrl := false             # standing jump: a direction was pressed in the air
var _core_setting := false
var _land_run := 0                # frames left of the k0/24 run start after a landing
var _vel_out := Vector3.ZERO      # velocity as the core left it (anything else = set from outside)
var _edge_fell := false           # this fall off an edge had its first (3 cm, velocity 0) frame
## Falcon's double jump (BUG-9, o_flow_start / o_hits_down P2): A while rising, at least DJ_MIN_F frames into state 5
## (a tap 2 frames in did nothing, 6 and 8 frames in did it: provisional bound) = k3/16 (its first row still moves,
## then 3 rows frozen in the air), then k0/7 at 28 cm/frame up (the first row moves 20), gravity 2; once per jump.
## The other fighters' A in the air: nothing was logged (not tested yet).
const DJ_MIN_F := 6
const DJ_HOLD := 3
const DJ_VY := 28.0
const DJ_LIFT := -8.0
var dj_t := -1
const STUCK_F := 6
var _stuck_n := 0
var dj_used := false

## The original's per-fighter movement table (1ST_READ 0x0C339540, tools/move_table.py, checked on the disc's 16 CPU
## fights): [4] jump vy, [6] jump gravity (negative), [7] air control, [10] / [11] wall kick-off up / out, [13] moving
## jump add, [14] run. Falcon / Ryoma: 35.5 / -2 / 10.5 / 25 / 2 / 0.25 / 9.5 = the constants above.
static var _mtab := {}
func _mv(i: int) -> float:
	if _mtab.is_empty() and FileAccess.file_exists("res://assets/fidelity/move_table.json"):
		_mtab = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/move_table.json"))
	var row: Array = (_mtab.get(char_id, _mtab.get("falcon", {})) as Dictionary).get("pc1" if powered else "pc0", [])
	if i < row.size(): return float(row[i])
	return [-2.0, 4.6, 3.0, 7.0, JUMP_VY, 0.0, -GRAV_CM, AIR_CM, 35.5, -2.0, 25.0, 2.0, 7.5, 0.25, RUN_CM][mini(i, 14)]

static func _ang(v: Vector3) -> float: return atan2(v.x, v.z)
static func _dir(a: float) -> Vector3: return Vector3(sin(a), 0, cos(a))
static func _wrap(a: float) -> float: return wrapf(a, -PI, PI)

func _gplay(kind: int, mot: int) -> void:
	if not (model is PSModel): return
	var pm := model as PSModel
	var idle := pm.clip_for("idle")
	if idle.length() < 2: return
	var c := "%sk%d_%03d" % [idle.substr(0, 2), kind, mot]
	var hit := false
	for n in ["idle", "run", "run_stop", "jump_start", "jump", "jump_move", "land", "pick_up", "carry", "carry_run"]:   # the clipmap's own names first
		if pm.has_clip(n) and pm.clip_for(n) == c:
			pm.play(n); hit = true; break
	if not hit and (pm.players.get(pm.form) as AnimationPlayer).has_animation(c): pm.play(c); hit = true
	# the original switches motions on the frame (no cross-fade frame: fx-pc / fx-cov BUG-55 saw k0/5 one row long)
	var tr: AnimationTree = pm.trees.get(pm.form)
	if hit and tr and tr.is_inside_tree() and pm.current_clip() != c:
		(tr.get("parameters/playback") as AnimationNodeStateMachinePlayback).start(c, true); tr.advance(0.0)

var gst_hist: Array = []          # debug: the last gst changes (frame, gst, rx_on, thr_on, pc_on) for test failure lines

func _gset(g: int, coarse: int) -> void:
	gst_hist.append([Engine.get_physics_frames(), g, rx_on, thr_on, pc_on, hp])
	if gst_hist.size() > 8: gst_hist.pop_front()
	if carry and g in [0, 2, 31, 32, 35]: coarse = S.CARRY
	dj_t = -1
	if g != 5: dj_used = false
	gst = g; gst_t = 0; vcm.x = 0.0; vcm.z = 0.0
	if g != 5 and g != 14 and g != 31: vcm.y = 0.0
	if coarse != state:
		_core_setting = true
		var prev := state
		state = coarse; state_t = 0.0
		var by: Fighter = last_hit_by if last_hit_by else opponent
		if by: by.combo_hits = 0
		if model is PSModel: (model as PSModel).root_motion = false
		_core_setting = false
		if prev == S.JUMP or coarse != S.JUMP: air_attacked = air_attacked and coarse == S.JUMP
	if item and _item_gplay(g): return   # fx-item2 hook: the item's carry family
	match g:
		0: _gplay(2, 220) if carry else _gplay(0, 0)
		2: _gplay(2, 221) if carry else _gplay(0, 3)
		4: _gplay(2, 222) if carry else _gplay(0, 5)   # jumping with an object overhead: k2/222 > k2/223 (OBJ.md 4)
		5: _gplay(2, 223) if carry else _gplay(0, 10 if air_move else 6)
		6: _gplay(2, 224) if carry else _gplay(0, 9)   # the carry landing (fx-cpu3: disc state 6 k2/224)
		14: _gplay(2, 223) if carry else _gplay(0, 6)
		31: _gplay(2, 221) if carry else _gplay(0, 24 if _land_run > 0 else 25)
		32: _gplay(2, 220) if carry else _gplay(0, 26)
		35: _gplay(2, 219)

func _core_tick(dt: float) -> void:
	if _mv_tick(dt): return   # fx-mv: the dive / curved turn / vault / ledge hang own this frame
	state_t += dt
	invuln = maxf(0.0, invuln - dt)
	gst_t += 1
	reach_obj = _reach_prop()
	if not velocity.is_equal_approx(_vel_out): vcm = velocity / CM_S   # pushed from outside (tests, cinematics, props)
	if gst not in [0, 2, 4, 5, 6, 14, 31, 32, 35]:   # back from a remaster-side state (attack, pole ...)
		_grounded = is_on_floor()
		gst = {S.IDLE: 0, S.RUN: 31}.get(state, 14); gst_t = 1
	var mv := _move_dir()
	var has_mv := mv.length() > 0.1
	var on_floor := grounded()
	# --- the state's handler: velocity for this frame
	match gst:
		0, 2, 6:
			vcm.x = 0.0; vcm.z = 0.0
			if gst == 2 and carry:   # the carry walk: disc state 2 k2/221 at the move table's [3] (Ryoma 7.0, Ayame 7.4 ...)
				if has_mv: facing = mv.normalized()
				var dw := _wrap(_ang(facing) - head)
				head = _wrap(head + (signf(dw) * RUN_TURN if absf(dw) >= RUN_TURN else dw * 0.5))
				vcm.x = _dir(head).x * _mv(3); vcm.z = _dir(head).z * _mv(3)
		4, 35:
			vcm = Vector3.ZERO
		31:
			if has_mv: facing = mv.normalized()
			var d := _wrap(_ang(facing) - head)
			head = _wrap(head + (signf(d) * RUN_TURN if absf(d) >= RUN_TURN else d * 0.5))
			var sp := START_CM if _land_run > 0 else _mv(14)
			if not has_mv and _land_run == 0: sp = 0.0   # the stick let go: the stop starts on this frame, no run step (move_basic P2 f6)
			if _land_run > 0:
				_land_run -= 1
				if _land_run == 0: _gplay(0, 25)
			vcm.x = _dir(head).x * sp; vcm.z = _dir(head).z * sp
		32:
			var k := gst_t
			var sp := _mv(14) * maxf(0.0, 7.0 - k) / 6.0 if k <= 6 else 0.0
			vcm.x = _dir(head).x * sp; vcm.z = _dir(head).z * sp
		5, 14:
			if on_floor and gst_t > 1 and vcm.y <= 0.0 and dj_t < 0:   # the floor was reached last frame: this is the
				vcm = Vector3.ZERO                                      # landing frame, no move (mv_jump f51: x 162.74)
			elif dj_t >= 0:   # Falcon's double jump (logged, o_flow_start): k3/16 row 0 moves, 3 rows held, then k0/7
				dj_t += 1
				if dj_t <= DJ_HOLD: vcm.y = 0.0; vcm.x = 0.0; vcm.z = 0.0
				elif dj_t == DJ_HOLD + 1:
					_gplay(0, 7); vcm.y = DJ_VY
				else: vcm.y -= GRAV_CM
			elif gst == 5 and gst_t == 1:
				vcm.y = _mv(4)
				if air_move:
					vcm.x = _dir(head).x * (_mv(14) + _mv(13)); vcm.z = _dir(head).z * (_mv(14) + _mv(13))
			elif gst_t > 1 or gst == 14:
				vcm.y -= GRAV_CM if gst == 14 else -_mv(6)
			if gst == 5 and gst_t > 1 and not (dj_t >= 1 and dj_t <= DJ_HOLD):
				if air_move:
					var sp := _mv(14) + _mv(13) if not has_mv or mv.dot(_dir(head)) > -0.5 else _mv(14) - _mv(13)
					vcm.x = _dir(head).x * sp; vcm.z = _dir(head).z * sp
				elif has_mv:
					air_ctrl = true
					var dd := mv.normalized() * _mv(7)
					vcm.x = dd.x; vcm.z = dd.z
	if item: _item_vel(mv, has_mv)   # fx-item2 hook: walking / family 195's stop while holding an item
	# ran off a step: still running (state 31), falling. The disc's first frame off the edge drops 3 cm with the
	# velocity still 0, then gravity 2 from -2 (o_ledge_londo: 240 > 237 > 235 > 231 > 225 ...)
	var edge_f := gst == 31 and not on_floor and vcm.y == 0.0 and not _edge_fell
	if gst == 31 and not on_floor:
		if edge_f: _edge_fell = true
		else: vcm.y -= GRAV_CM
	elif gst in [0, 2, 6, 31, 32] and on_floor and vcm.y < 0.0: vcm.y = 0.0
	if on_floor: _edge_fell = false
	# --- move (the first rising frame moves 3 cm less, logged; the double jump's first rising frame 8 less)
	var lift := -3.0 if (gst == 5 and gst_t == 1 and dj_t < 0) or edge_f else 0.0
	if dj_t == DJ_HOLD + 1: lift = DJ_LIFT
	var was_floor := on_floor
	_core_move(Vector3(vcm.x, vcm.y + lift, vcm.z), on_floor)
	_mv_after_move()   # fx-mv: the pole bump, the hop boxes
	on_floor = grounded()
	# --- transitions (the remaster's buttons: attacks, grabs, pick-ups, poles, drives / fusions)
	match gst:
		0, 2, 31, 32:
			if item and _item_ground(has_mv, mv): return   # fx-item2 hook: use / walk while holding an item
			if carry and (ic.is_pressed("punch") or ic.is_pressed("kick")):
				_throw_carry()
				return
			if carry and ic.is_pressed("action"):
				_drop_carry(true)
			if not on_floor and gst != 31:
				_gset(14, S.JUMP)
			elif ic.is_pressed("jump") and not carry and (ic.is_pressed("punch") or ic.is_pressed("kick")) and _core_actions():
				return   # a ground attack beats a jump pressed on the same frame (BUG-54, mash_s44 f12: k1/24 for 43 rows)
			elif ic.is_pressed("jump"):   # carrying too (the disc jumps with the object: k2/222 > 223; fx-cpu3: the AI's
				if gst == 31 or gst == 2:   # JUMP 6 at Londo's fountain was blocked while carrying, a BUG-41 loop)
					air_move = true; air_ctrl = false; air_attacked = false
					_gset(5, S.JUMP)
				else:
					air_move = false; air_ctrl = false; air_attacked = false
					_gset(4, S.JUMP)
			elif not carry and _core_actions():
				return
			elif _mv_dodge() or _mv_hop():   # fx-mv: the dodge (state 7), the hop onto a box (state 17)
				return
			elif carry:   # carrying: walk (state 2, k2/221) while the stick is held, else stand (state 0, k2/220) at once:
				if has_mv and gst != 2:   # the disc has no run / stop slide with an object (CPU logs: 5,560 rows of 221 in
					facing = mv.normalized()   # state 2, 2,736 of 220 in state 0, 221 > 220 directly 77 times)
					if gst == 0: head = _ang(facing)
					_gset(2, S.CARRY)
				elif not has_mv and gst != 0:
					_gset(0, S.CARRY)
			elif gst == 2:
				_land_run = 8
				_gset(31, S.RUN)
			elif gst == 31 and not has_mv:
				_land_run = 0
				_gset(32, S.RUN)
			elif gst in [0, 32, 2] and has_mv:
				facing = mv.normalized()
				if gst == 0: head = _ang(facing)
				_gset(31, S.RUN)
			elif gst == 32 and gst_t >= STOP_LEN:
				_gset(0, S.IDLE)
		4:
			if gst_t >= CROUCH_F: _gset(5, S.JUMP)
		35:
			if item: _item_pick_tick()   # fx-item2 hook: the item pick-up's rows
			elif gst_t >= PICK_F: _gset(0, S.CARRY)
		5, 14:
			if item and (ic.is_pressed("punch") or ic.is_pressed("kick")): air_attacked = true   # fx-item2 hook: no air use yet
			if gst == 5 and dj_t < 0 and not dj_used and char_id == "falcon" and gst_t >= DJ_MIN_F and ic.is_pressed("jump"):
				dj_used = true; dj_t = 0
				_gplay(3, 16)
			elif carry and (ic.is_pressed("punch") or ic.is_pressed("kick")) and not air_attacked:
				air_attacked = true   # the airborne carry throw: k2/225 on the jump's own arc, release on its 15th frame
				if _core_throw(true): return
			elif (ic.is_pressed("punch") or ic.is_pressed("kick")) and not air_attacked and not powered and not carry:
				air_attacked = true
				if _core_attack("AX" if ic.is_pressed("punch") else "AY"): return
				vel_to_legacy()
				_start_attack("air")
				return
			if powered and (ic.is_pressed("punch") or ic.is_pressed("kick")) and not air_attacked and not carry \
					and _pc_attack("AX" if ic.is_pressed("punch") else "AY"):   # air Power Drives (fx-pc)
				air_attacked = true
				return
			if (ic.is_pressed("punch") or ic.is_pressed("kick")) and not air_attacked and not carry:
				air_attacked = true
				vel_to_legacy()
				_start_attack("air")
				return
			if ic.is_pressed("jump") and not carry and not wk_used and has_mv and _core_wallkick():
				return
			elif ic.is_pressed("action") and not carry and (_mv_hang36() or _try_pole()):   # docs/OBJ.md 1: only on the ACTION press
				return
			elif ic.is_pressed("action") and not carry and _mv_air_action():   # fx-mv BUG-53: nothing caught = the air punch
				return
			if on_floor and was_floor and vcm.y <= 0.0 and gst_t > 1:   # floor reached last frame: land now
				air_attacked = false; wk_used = false
				if air_move and has_mv:
					facing = mv.normalized(); head = _ang(facing)
					_gset(31, S.RUN)
				else:
					_gset(6, S.IDLE)
					gst = 6
		6:
			if gst_t >= LAND_F:
				if has_mv:
					facing = mv.normalized(); head = _ang(facing)
					_gset(2, S.RUN)
				else:
					_gset(0, S.IDLE)
	_apply_facing()
	_carry_pose()

func vel_to_legacy() -> void:
	velocity = vcm * CM_S

## Ground buttons from idle / run / stop (the remaster's move selection until the attack port): true when one started
func _core_actions() -> bool:
	var was := state
	if powered and (ic.is_pressed("fusion1") or (ic.is_held("jump") and ic.is_pressed("punch"))) and _pc_attack("FX"): return true
	if powered and (ic.is_pressed("fusion2") or (ic.is_held("jump") and ic.is_pressed("kick"))) and _pc_attack("FY"): return true
	if _mv_act():   # no pole catch from the ground: every one of the 83 catches in the disc's CPU fights
		# came out of a jump (state 5 > 34 with action pressed) and standing presses never caught one (tools/poleprobe.py)
		if _try_grab(): return true
		if _item_pickup(): return true   # fx-item2 hook: a ready floor item in reach
		if _try_pickup(): return true
		if _mv_action_attack(): return true   # fx-mv BUG-53: nothing in reach = the fighter's first attack (Rouge: kick)
	for b in [["punch", "X"], ["kick", "Y"]]:
		if not ic.is_pressed(b[0]): continue
		if powered:   # Power Drives: the logged rows of this fighter's move (fx-pc), else the remaster's old drive
			if _pc_attack(b[1]): return true
			if Rules.can_drive(gauge): _start_attack("drive_p" if b[1] == "X" else "drive_k")
			else: _start_attack("punch1" if b[1] == "X" else "kick1")
			return true
		if _core_obj_punch(b[1]): return true
		var cat: String = b[1]
		if gst == 31: cat = "R" + cat
		elif _opp_near(): cat += "_near"
		if _core_attack(cat): return true
		_start_attack("punch1" if b[1] == "X" else "kick1")
		return true
	return state != was

## Object punch (docs/OBJ.md 3, fx-obj; select 0x0C0A1BF0, init 0x0C063EAC): the first ground punch / kick of a
## string, not in Power Change, with a throwable at rest touching me (the core's pick-up reach). Punch: the heading to
## the opponent (0x0C09DB78) against the heading to the object: 90 deg or more = turned toward the object (+0x30 = to
## the opponent + 0x8000, the body faces it), k1/153 10 frames in place, then k1/154 49 frames moving 4.0816 cm/frame
## along +0x30 (float 0x0C0640EC), and on k1/154 frame 6 the object flies back over him at the opponent (90 of 90 /
## 9 of 9 logged); less than 90 deg = facing the opponent, k1/78 33 frames, the object leaves on frame 8 straight and
## level at him (11 of 11). Kick: only with the object within 60 deg of the heading: k1/59 33 frames.
## The flung object (OBJ.md 6b, 49 of 50 logged releases): it leaves from where it lies (it is only touched), at its own
## rest height, level, straight at the opponent (k1/78 along +0x30; k1/154 along +0x30 + 180 deg, which points at him
## too), at Prop.fly_cm (15 / 20 by its property + the thrower's bonus).
const VAULT_CM := 4.0816
var reach_obj: Node3D = null      # +0x71C8: the carried object, else the stage object a punch would act on
var _fling_obj: Node3D = null
var _fling_f := -1

func _reach_prop() -> Node3D:
	if carry and is_instance_valid(carry): return carry
	if not arena or not arena.has_method("nearest_prop"): return null
	return arena.nearest_prop(global_position, 1.45)

func _core_obj_punch(btn: String) -> bool:
	if carry or opponent == null or powered or not (model is PSModel): return false
	var o := _reach_prop()
	if o == null: return false
	var to_opp := opponent.global_position - global_position; to_opp.y = 0
	var to_obj := o.global_position - global_position; to_obj.y = 0
	if to_opp.length() < 0.01 or to_obj.length() < 0.01: return false
	var d := absf(_wrap(_ang(to_opp) - _ang(to_obj)))
	if btn == "Y":
		if absf(_wrap(_ang(facing) - _ang(to_obj))) > deg_to_rad(60.0) or not _motion_start("k1_059", false): return false
		_fling_obj = o; _fling_f = 8
	elif d >= PI * 0.5:
		if not _motion_start("k1_153", false): return false
		atk_ref = _wrap(_ang(to_opp) + PI); facing = _dir(atk_ref); _apply_facing()
		_fling_obj = o; _fling_f = -1   # set on k1/154's start
	else:
		if not _motion_start("k1_078", false): return false
		_fling_obj = o; _fling_f = 8
	vcm = Vector3.ZERO
	return true

## The punched object leaves level, straight at the opponent (k1/78 frame 8, k1/154 frame 6, k1/59 frame 8)
func _obj_fling() -> void:
	var o := _fling_obj
	_fling_obj = null; _fling_f = -1
	if o == null or not is_instance_valid(o) or not (o is Prop) or (o as Prop).state != Prop.REST: return
	var from := o.global_position
	var d := (opponent.global_position - from) if opponent else _dir(atk_ref)
	d.y = 0
	var f := d.normalized() if d.length() > 0.001 else _dir(atk_ref)
	(o as Prop).launch(self, from, f * (o as Prop).fly_cm(char_id, false) * CM_S)
	stats.objects_thrown += 1

## Move by d (cm this frame) against the stage: walls slide (move_and_slide), floors up to STEP_UP_CM higher are
## stepped onto in one frame like the original's, floors below are fallen to with gravity.
func _core_move(d: Vector3, on_floor: bool) -> void:
	if _cg_on():
		_core_move_cg(d); return
	var dh := Vector3(d.x, 0, d.z) * 0.01
	if on_floor and dh.length() > 0.0001 and is_inside_tree():
		var to := global_position + dh
		var q := PhysicsRayQueryParameters3D.create(to + Vector3.UP * (STEP_UP_CM * 0.01 + 0.05), to + Vector3.DOWN * 0.05, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit and float(hit.position.y) > global_position.y + 0.02 and float(hit.position.y) <= global_position.y + STEP_UP_CM * 0.01:
			global_position.y = float(hit.position.y) + 0.001
	velocity = d * CM_S
	var snap := floor_snap_length
	floor_snap_length = 0.0 if d.y > 0.0 else 0.35
	var before := global_position
	move_and_slide()
	floor_snap_length = snap
	_grounded = is_on_floor()
	# H-12: a body wedged against stage geometry in the air (move_and_slide spends every slide at depth 0, the position
	# never changes while the fall speed grows) is nudged out along the contact after 6 frames; the original never
	# leaves a fighter hanging
	if not grounded() and d.length() > 0.5 and (global_position - before).length() < 0.002: _stuck_n += 1
	else: _stuck_n = 0
	if _stuck_n >= STUCK_F:
		var n := Vector3.ZERO
		for i in get_slide_collision_count(): n += get_slide_collision(i).get_normal()
		n.y = 0.0
		if n.length() < 0.01 and arena and arena.has_method("clamp_point"):   # no wall normal: toward the area's inside
			var q: Vector3 = arena.clamp_point(global_position, 0.6)
			n = Vector3(q.x - global_position.x, 0, q.z - global_position.z)
		global_position += (n.normalized() if n.length() > 0.01 else -facing) * 0.1
		_stuck_n = 0
	if arena: arena.clamp_fighter(self)
	_vel_out = velocity


## --- core step 2: attacks by the original's own motion ids (game/assets/fidelity/chains.json: the first motion per
## button / place, press links and automatic follow-ups, all read off the reference logs by tools/chain_table.py),
## its per-frame travel (motions.json, toward the opponent at the motion's start: the game turns attacks to face him),
## chain presses taken once the motion's last attack step has ended (Pn0_HIT.BIN, logged: Ryoma 16 > 17 at frame 12),
## and the attacker's 8-frame hit-stop. Air attacks keep the jump's own physics (logged: k1/10 follows the parabola).
const HITSTOP_ATK := 8
const NEAR_CM := 120.0            # near_*.tape: k1/74 at 100 cm, k1/16 at 120+ once the victim has been knocked about
                                  # (the original probably also needs him facing you: his body facing isn't logged yet)
static var _chains := {}
static var _motions := {}
var core_atk := false
var gmo := ""                     # "k1_016" (P prefix: Power Change form)
var gmo_f := 0
var gmo_n := 0
var gmo_air := false
var atk_ref := 0.0
var atk_open := 0
var hit_stop := 0
var _pbuf := {"X": 99, "Y": 99}
var _tr_sum := Vector3.ZERO       # the core motion's table travel so far (side, up, forward; cm)

static func _tables() -> void:
	if _chains.is_empty() and FileAccess.file_exists("res://assets/fidelity/chains.json"):
		_chains = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/chains.json"))
		_motions = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/motions.json"))

func _opp_near() -> bool:
	if opponent == null: return false
	var d := Vector2(opponent.global_position.x - global_position.x, opponent.global_position.z - global_position.z).length() * 100.0
	return d < NEAR_CM and opponent.gst in [0, 2, 4, 5, 6, 31, 32]

func _clip_prefix() -> String:
	if not (model is PSModel): return ""
	var idle := (model as PSModel).clip_for("idle")
	return idle.substr(0, 2) if idle.length() >= 2 else ""

func _core_attack(cat: String) -> bool:
	_tables()
	var t: Dictionary = _chains.get(char_id, {})
	var first: Dictionary = t.get("first", {})
	var key: String = first.get(cat, first.get(cat.trim_prefix("R").trim_suffix("_near"), ""))
	if key == "" or not _motion_start(key, cat.begins_with("A")): return false
	if not cat.begins_with("A"): vcm = Vector3.ZERO
	return true

func _motion_start(key: String, air: bool) -> bool:
	var clip := _clip_prefix() + key
	if not (model is PSModel) or not ((model as PSModel).players.get((model as PSModel).form) as AnimationPlayer).has_animation(clip):
		return false
	gmo = key; gmo_f = 0; gmo_air = air
	_tr_sum = Vector3.ZERO
	var mt: Dictionary = (_motions.get(char_id, {}) as Dictionary).get(clip, {})
	var clen := int(round(((model as PSModel).players[(model as PSModel).form] as AnimationPlayer).get_animation(clip).length * 60.0)) + 1
	gmo_n = maxi(int(mt.get("n", 0)), clen)
	atk_open = 0
	if ghits and ghits.ok:
		var w := ghits.active_window(key)
		if w.y >= 0: atk_open = w.y + 1
	if opponent and not air:
		var d := opponent.global_position - global_position; d.y = 0
		if d.length() > 0.05: facing = d.normalized()
	atk_ref = _ang(facing)
	cur_attack = {"k1_016": "punch1", "k1_017": "punch2", "k1_018": "punch3", "k1_024": "kick1", "k1_025": "kick2",
		"k1_010": "air", "k1_012": "air"}.get(key, "punch3" if key.begins_with("k1") else "punch1")
	attack_hit = false; _hit_mark = ""
	core_atk = true
	_core_setting = true
	state = S.ATTACK; state_t = 0.0
	_core_setting = false
	gst = 11 if powered else 10; gst_t = 0
	(model as PSModel).root_motion = false
	(model as PSModel).play(clip)
	(model as PSModel).time_scale = 1.0
	_pbuf = {"X": 99, "Y": 99}
	_apply_facing()
	return true

func _core_attack_tick(dt: float) -> void:
	state_t += dt
	invuln = maxf(0.0, invuln - dt)
	gst_t += 1
	for b in [["punch", "X"], ["kick", "Y"]]:
		_pbuf[b[1]] = 0 if ic.is_pressed(b[0]) else int(_pbuf[b[1]]) + 1
	if model is PSModel: (model as PSModel).time_scale = 0.0 if hit_stop > 0 else 1.0
	if hit_stop > 0:   # the game stops the attacker's motion and travel while the hit lands
		hit_stop -= 1
		_core_move(Vector3.ZERO, grounded())
		return
	gmo_f += 1
	if (gmo == THROW_KEY or gmo == AIR_THROW_KEY) and carry and gmo_f == THROW_RELEASE_F: _release_carry()
	if _fling_f >= 0 and gmo_f == _fling_f and gmo in ["k1_078", "k1_154", "k1_059"]: _obj_fling()
	if cur_attack == "item": _item_use_tick()   # fx-item2 hook: the use's shot / reach / release
	# travel: the original's own per-frame displacement for this motion (air attacks: the jump's physics)
	var on_floor := grounded()
	var d := Vector3.ZERO
	if gmo_air:
		vcm.y -= -_mv(6)   # the jump's own gravity carries on through an air attack
		d = vcm
	else:
		var mt: Dictionary = (_motions.get(char_id, {}) as Dictionary).get(_clip_prefix() + gmo, {})
		var rows: Array = mt.get("d", [])
		if gmo == "k1_154" and gmo_f >= 1:   # 4.0816 cm/frame along +0x30 (turned toward the object at k1/153's start)
			d = _dir(atk_ref) * VAULT_CM
		elif gmo_f < rows.size():
			var r: Array = rows[gmo_f]
			var f := _dir(atk_ref); var sd := Vector3(f.z, 0, -f.x)
			d = f * float(r[0]) + sd * float(r[1]) + Vector3.UP * float(r[2])
			_tr_sum += Vector3(float(r[1]), float(r[2]), float(r[0]))   # (side, up, forward) cm: the clip carries it too
		if not on_floor: vcm.y -= GRAV_CM
		else: vcm.y = 0.0
		d.y += vcm.y
		vcm = Vector3(d.x, vcm.y, d.z)
	_core_move(d, on_floor)
	if model is PSModel:   # fx-reach: game frame gmo_f's pose (clip frame - 1), the hip where the disc draws it (docs/REACH.md)
		(model as PSModel).core_frame(_clip_prefix() + gmo, gmo_f, Vector3.ZERO if gmo_air else -_tr_sum * 0.01)
	_carry_pose()
	var before: int = int(stats.hits)
	_game_hit_update()
	if stats.hits > before: hit_stop = _rx_stop if _rx_stop >= 0 else HITSTOP_ATK
	hitstop = 0.0   # the remaster's seconds-based hit-stop is replaced by the game's frames here
	# chain presses once the last attack step is over, then the motion's automatic follow-up, then free
	var t: Dictionary = _chains.get(char_id, {})
	var links: Dictionary = (t.get("links", {}) as Dictionary).get(gmo, {})
	if gmo_f >= atk_open:   # a press 1 frame before the window still counts, older ones don't (disc logs: 184 links
		for b in ["X", "Y"]:   # 2 frames after the press, 6 one frame late = pressed 1 frame early, 0 with an older press)
			if int(_pbuf[b]) <= 1 and links.has(b) and _motion_start(str(links[b]), gmo_air):
				return
	if gmo_air and grounded() and gmo_f > 2:
		core_atk = false
		_gset(6, S.IDLE)
		return
	if gmo_f >= gmo_n - 1:
		if gmo == "k1_153":   # 0x0C064056: k1/154 on the same turned-round heading (not re-aimed at the opponent)
			var h := atk_ref
			var ob := _fling_obj
			if _motion_start("k1_154", false):
				atk_ref = h; facing = _dir(h); _apply_facing()
				_fling_obj = ob; _fling_f = 6
				return
		var nx: String = (t.get("auto", {}) as Dictionary).get(gmo, "")
		if nx != "" and _motion_start(nx, gmo_air): return
		core_atk = false
		if gmo_air and not grounded(): _gset(5, S.JUMP); gst_t = 2
		else: _gset(0, S.IDLE)


## --- core step 3a: carrying and throwing stage objects, logged on the disc (items_londo tape + the chair's object
## record 0x0C7D5A50 per frame: its world position at +0xA4; Ryoma on Londo): B next to an object = state 35, k2/219
## for 18 frames, the object in the hand from the first frame; then the core's own idle / run with the carry motions
## k2/220 / k2/221 (state 0 / 31: carrying is not a state of its own); X or Y = state 10, the throw motion for 36
## frames; on its 15th frame the object leaves from 50 cm in front of the thrower's feet, 117 cm up, and flies a
## straight line at 20.0 cm/frame toward the opponent's hip (19.61 forward + 3.93 up on the logged throw: no gravity on
## the way); it breaks on the hit and is back on its home spot 2 frames later.
## Not ported yet: the object's spin in the hand, per-object damage (the chair hit for base 40, a plant base 25: the remaster
## still uses one base 32), what a miss does after the logged 8 frames (provisional: straight for 30 frames, then
## gravity 2 cm/frame^2), running speed while carrying.
const PICK_F := 18
const THROW_KEY := "k1_060"
const THROW_F := 36
const THROW_RELEASE_F := 15
const THROW_FROM := Vector3(50.0, 80.0, 0.0)      # cm: forward, up, side of the thrower's feet (OBJ.md 6b; Gunrock 60 / 96)
const THROW_CM := 20.0                             # cm/frame
const THROW_AIM_UP := 107.0                        # cm over the target's feet (the logged line ends at the hip)
const CARRY_AT := Vector3(-13.2, 248.5, -11.1)     # cm: forward, up, side (the logged carry: over the head)
const PICK_UP_Y := [79.2, 80.1, 81.0, 81.9, 105.8, 129.2, 156.4, 177.6, 190.3, 193.2, 211.9, 228.5, 242.4, 253.1,
	260.3, 257.4, 253.7, 249.2]                    # cm: the object's height over the feet per pick-up frame (logged)
var _carry_from := Vector3.ZERO

func _local_cm(v: Vector3) -> Vector3:   # (forward, up, side) cm in this fighter's facing -> world metres
	var f := _dir(_ang(facing)); var sd := Vector3(f.z, 0, -f.x)
	return (f * v.x + Vector3.UP * v.y + sd * v.z) * 0.01

func _carry_pose() -> void:
	if not carry or not is_instance_valid(carry): return
	var to := global_position + _local_cm(CARRY_AT)
	if gst == 35 and gst_t < PICK_F:   # rising to the hold along the logged height curve
		var k := clampf(float(gst_t) / float(PICK_F - 1), 0.0, 1.0)
		var p := _carry_from.lerp(to, k)
		p.y = global_position.y + float(PICK_UP_Y[mini(gst_t, PICK_F - 1)]) * 0.01
		carry.global_position = p
	else:
		carry.global_position = to

const AIR_THROW_KEY := "k2_225"
func _core_throw(air := false) -> bool:
	if not (model is PSModel): return false
	if opponent:   # the body turns to the opponent (the logged object flew at him whatever the stick said)
		var d := opponent.global_position - global_position; d.y = 0
		if d.length() > 0.05: facing = d.normalized()
	gmo = AIR_THROW_KEY if air else THROW_KEY; gmo_f = 0; gmo_n = THROW_F + 1; gmo_air = air; atk_open = 999   # n - 1 frames after the start one
	atk_ref = _ang(facing)
	cur_attack = "throw"; attack_hit = false; _hit_mark = ""
	core_atk = true
	_core_setting = true
	state = S.ATTACK; state_t = 0.0
	_core_setting = false
	gst = 10; gst_t = 0
	if not air: vcm = Vector3.ZERO
	var pm := model as PSModel
	pm.root_motion = false
	var tc := _clip_prefix() + (AIR_THROW_KEY if air else THROW_KEY)   # the disc's k1/60 (captured 10-27, docs/CLIPS.md); k1/78 before that
	if (pm.players.get(pm.form) as AnimationPlayer).has_animation(tc): pm.play(tc)
	elif pm.has_clip("throw"): pm.play("throw")
	pm.time_scale = 1.0
	_pbuf = {"X": 99, "Y": 99}
	_apply_facing()
	return true

func _release_carry() -> void:
	var c := carry
	carry = null
	var from := global_position + _local_cm(Vector3(60.0, 96.0, 0.0) if char_id == "gunrock" else THROW_FROM)
	var aim := from + _dir(_ang(facing)) * 3.0
	if opponent: aim = opponent.global_position + Vector3.UP * THROW_AIM_UP * 0.01
	var sp: float = c.call("fly_cm", char_id, true) if c.has_method("fly_cm") else THROW_CM
	var v := (aim - from).normalized() * sp * CM_S if (aim - from).length() > 0.01 else facing * sp * CM_S
	if c.has_method("launch"): c.call("launch", self, from, v)
	else: c.call("throw_from", self, v)
	stats.objects_thrown += 1


## --- core step 3b: the original's hit-reaction machine (docs/REACT.md, decoded from 1ST_READ state 27 = 0x0C08ED56
## by the fx-react helper and checked on 374 logged hits by tools/react_sim.py; tables + every fighter's 20-byte attack
## records: game/assets/fidelity/react_code.json). Row 0 = the frame the hit lands (state 27, motion unchanged); row 1
## = the class handler's first step; rec[2] - 2 frozen rows; then the class: 0 standing hit (k2/base > +1 sliding by the
## knockback table along atan2(victim - attacker) - rec[0xe] x 11.25 deg > +2, state 24 for 8 rows), 1/2 launch from the
## hip (v = launch_speed[rec[0xc]] at rec[0xd] x 11.25 deg up, gravity -2; k2/96|128 > +1 > +2 > landing 99|131 >
## lying 144|145 5 rows > get-up 146|147 23 rows + k0/0 7), 3 tumble (k2/112, bounce 11.6 / -2.97 as k2/115, 2 rows on the floor), walls
## during a launch: splat (class 22: k2/152 119 cm lower, 20 rows stuck, slide at -1, k2/153 40 rows, lying). The stun
## meter (20, minus rec[7] & 63 per hit) empties into a dizzy launch (level 6, elevation 7) that ends in k2/175.
## Not ported (the remaster's old reaction runs instead): classes 5-29 other than these, hits on a lying fighter (13),
## guard, the lying-length rule (5 rows; 10 in 23 of 89 logged), the wall splat-or-bounce test (splat unless rec[0x10]
## & 1), the stun refill (180 quiet frames, assumed), air / wall techs.
const REACT_CORE := true
const ANG16 := 65536.0
static var _rx := {}
var rx_on := false
var rx_cls := 0
var rx_rec := PackedByteArray()
var rx_row := 0
var rx_m := 0               # the k2 motion on display (1000 + n = k0/n)
var rx_m0 := 0
var rx_base := 0
var rx_freeze := 0
var rx_f0 := 0
var rx_kb: Array = []
var rx_i := 0
var rx_sub := 0
var rx_head := 0.0          # knockback heading (radians, game convention: 0 = +z)
var rx_v := Vector3.ZERO    # cm/frame (launches)
var rx_g := -2.0
var rx_fall := 0.0   # cm/frame: a standing hit's knockback off a ledge falls meanwhile (BUG-105)
var rx_ec := 0
var rx_fr := 0
var rx_wait := 0
var rx_side := 0
var rx_phase := ""
const RX_BOUNCE_G := -2.97
var rx_walls := 0
var rx_mrow := 0            # rows the current motion has run
var rx_tail: Array = []     # [[game state, motion (1000 + n = k0/n), rows], ...] after the class's own rows
var rx_dizzy := false
var _rx_stop := -1
var stun := 20
var stun_quiet := 0

static func _rx_tables() -> void:
	if _rx.is_empty() and FileAccess.file_exists("res://assets/fidelity/react_code.json"):
		_rx = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/react_code.json"))

static func _u16(a: float) -> int:   # radians (game convention) -> the game's u16 angle
	return int(round(wrapf(a, 0.0, TAU) / TAU * ANG16)) & 0xFFFF

static func _s16(a: int) -> int:
	a &= 0xFFFF
	return a - 0x10000 if a & 0x8000 else a

func _rx_record(attacker: Fighter, hid: int) -> PackedByteArray:
	_rx_tables()
	if item_react_rec.size() == 20: return item_react_rec   # fx-item2 hook: an item's record (Items.apply_hit)
	if attacker == null or hid <= 0: return PackedByteArray()
	var recs: Array = (_rx.get("records", {}) as Dictionary).get(attacker.char_id, [])
	if hid >= recs.size(): return PackedByteArray()
	var hx: String = recs[hid]
	return hx.hex_decode() if hx.length() == 40 else PackedByteArray()

func _rx_len(m: int) -> int:   # rows a k2 motion runs before the machine moves on (logged lengths, else the clip's)
	var lm: Dictionary = (_rx.get("measured", {}) as Dictionary).get("len", {})
	if lm.has(str(m)): return int(lm[str(m)])
	if model is PSModel:
		var ap := (model as PSModel).players.get((model as PSModel).form) as AnimationPlayer
		var c := _clip_prefix() + "k2_%03d" % m
		if ap and ap.has_animation(c): return int(round(ap.get_animation(c).length * 60.0)) + 1
	return 10

func _rx_play(m: int) -> void:
	rx_m = m; rx_mrow = 0
	if m >= 1000: _gplay(0, m - 1000)
	elif model is PSModel:
		var pm := model as PSModel
		var c := _clip_prefix() + "k2_%03d" % m
		var cm: Dictionary = pm.clipmap.get(pm.form, {})
		for n in cm:   # the clipmap's own name when it maps there (watchers / cinematics read those names)
			if str(cm[n]) == c: pm.play(n); return
		if (pm.players.get(pm.form) as AnimationPlayer).has_animation(c): pm.play(c); return
		# most reaction motions are not captured yet (Motion Check capture pending): the nearest captured reaction
		var fb := "hit"
		if m in [96, 97, 98, 128, 129, 130, 112, 115]: fb = "down"
		elif m in [99, 131, 152, 153]: fb = "down"
		elif m in [144, 145]: fb = "lying"
		elif m in [146, 147]: fb = "getup"
		if pm.has_clip(fb) and pm.playing != fb: pm.play(fb)

## A landed hit with the game's record: true when the machine took it (else the remaster's old reaction runs)
var _rx_frame := -1   # the physics frame react_start ran on: the disc shows the hit frame with the motion unchanged
func react_start(attacker: Fighter, hid: int, from: Vector3) -> bool:
	if not REACT_CORE or boss: return false
	var rec := _rx_record(attacker, hid)
	if rec.size() != 20: return false
	var d := global_position - from; d.y = 0
	var att_dir := _u16(_ang(d)) if d.length() > 0.001 else _u16(_ang(-facing))
	var yaw := _u16(_ang(facing))
	var air := 2 if (rx_on and rx_phase in ["fly", "bounce", "settle"]) or gst in [4, 5, 14] or not grounded() else 0
	var lying := rx_on and rx_phase == "lie"
	if lying: return false   # class 13 (hit while lying): not decoded
	# 0x0C08E704: the class the machine runs
	var cls := int(rec[0])
	if cls != 23:
		if hp <= 0: cls = 1
		else:
			if air == 2 and cls < 25:
				if cls in [0, 4, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18]: cls = 1 if rec[4] == 0 else 2
				elif cls == 24: cls = 3
			if stun == 0 and cls not in (_rx.get("knockdown_classes", [1, 2, 3, 4, 5, 6, 16, 22]) as Array).map(func(v): return int(v)):
				cls = 2
	if cls not in [0, 1, 2, 3]: return false
	rx_dizzy = stun == 0 and cls == 2 and rec[0] != 2
	stun = maxi(0, stun - (int(rec[7]) & 63)); stun_quiet = 180
	var r14 := int(rec[14]) & 0x1F
	var dd := _s16((att_dir - r14 * 2048) - yaw)
	rx_side = 0
	if dd >= -0x1C71 and dd <= 0x1C71: rx_side = 1
	elif dd > 0x1C71 and dd <= 0x638E: rx_side = 2
	elif dd >= -0x638E and dd < -0x1C71: rx_side = 3
	rx_head = float((att_dir - r14 * 2048) & 0xFFFF) / ANG16 * TAU
	_throw_cancel()   # a hit on the thrower (Battle Royale: a third fighter) ends his throw
	rx_rec = rec; rx_cls = cls; rx_on = true; rx_row = 0; rx_walls = 0; rx_tail = []; wk_t = -1   # a hit ends a wall kick
	rx_freeze = maxi(0, int(rec[2]) - 2)
	rx_phase = "hit"
	core_atk = false; hit_stop = 0
	if carry: _drop_carry(true)
	if item: _item_drop()   # fx-item2 hook
	_core_setting = true
	state = S.DOWN if hp <= 0 else S.HITSTUN; state_t = 0.0   # a KO'd fighter's launch: down for good
	_core_setting = false
	gst = 27; gst_t = 0
	if model is PSModel: (model as PSModel).root_motion = false; (model as PSModel).time_scale = 1.0
	_rx_frame = Engine.get_physics_frames()
	return true

func _react_tick() -> void:
	if Engine.get_physics_frames() == _rx_frame: return   # hit by an attacker that ticked first: row 0 waits a frame
	state_t += 1.0 / 60.0
	gst_t += 1
	rx_row += 1
	rx_mrow += 1
	if model is PSModel: (model as PSModel).time_scale = 1.0
	if rx_phase == "tail":
		_rx_tail_tick(); return
	if rx_row == 1:
		_rx_step0(); return
	if rx_freeze > 0:   # hit-stop: the motion and the body hold
		rx_freeze -= 1
		if model is PSModel: (model as PSModel).time_scale = 0.0
		return
	match rx_cls:
		0: _rx_class0()
		_: _rx_launch()

func _rx_step0() -> void:
	var rec := rx_rec
	var lvl := int(rec[0xc]); var elev := int(rec[0xd])
	if rx_dizzy: lvl = 6; elev = 7
	if rx_cls == 0:
		var tbl: Array = _rx.get("motion_table", [])
		var col := int(rec[6]) - 1 if rec[6] != 0 else 2 + (3 if lvl > 3 else 0)
		rx_base = int(tbl[rx_side * 6 + col])
		rx_kb = ((_rx.get("knockback", []) as Array)[mini(lvl, 15)] as Array).filter(func(v): return float(v) >= 0.0)
		rx_f0 = maxi(1, int(rec[3]) - 1); rx_i = 0; rx_sub = 2; rx_fall = 0.0
		facing = -_dir(rx_head)   # the game turns him toward the hit (+0x30)
		_apply_facing()
		_rx_play(rx_base)
		return
	# launches: from the hip bone, v at elev x 11.25 deg, gravity -2
	var hip := _rx_hip()
	global_position = hip
	if arena: arena.clamp_fighter(self)   # the original's push keeps the moved body inside the area too
	var el := float(elev) * 2048.0 / ANG16 * TAU
	var sp: float = float((_rx.get("launch_speed", []) as Array)[mini(lvl, 15)])
	var f := _dir(rx_head)
	rx_v = f * sp * cos(el) + Vector3.UP * sp * sin(el)
	rx_g = -2.0
	if rx_cls == 3: rx_m0 = 112
	elif rec[0] in [1, 2] and rec[6] == 2:
		rx_m0 = 96 if rx_side == 1 else 128; rx_side = 0 if rx_side == 1 else 1
	elif rec[0] in [1, 2] and rec[6] in [3, 4]: rx_m0 = 112
	else: rx_m0 = 128 if rx_side == 1 else 96
	rx_ec = 0; rx_fr = 0; rx_wait = 3; rx_phase = "fly"
	facing = -f if rx_m0 != 128 else f
	_apply_facing()
	if hp <= 0 and powered: _set_powered(false)
	_rx_play(rx_m0)

func _rx_hip() -> Vector3:
	if model is PSModel:
		var sk := (model as PSModel).skeleton()
		if sk and sk.get_bone_count() > 0:
			var p := (sk.global_transform * sk.get_bone_global_pose(0)).origin
			if p.y > global_position.y + 0.3 and p.y < global_position.y + 1.6: return Vector3(p.x, p.y, p.z)
	return global_position + Vector3.UP * 0.9

func _rx_class0() -> void:
	if rx_sub == 2 and rx_i >= rx_kb.size():
		_rx_play(rx_base + 2); rx_sub = 3
		if rx_f0 < 2: rx_f0 += 1
	elif rx_sub == 2:
		if rx_mrow == 1 or rx_m != rx_base + 1:
			if rx_m != rx_base + 1: _rx_play(rx_base + 1)
		var step := float(rx_kb[rx_i]); rx_i += 1
		_core_move(_dir(rx_head) * step, grounded())
	# off the floor (knocked over a ledge's edge: Ryoma's stage, a 1.2 m floor, the body held 1.2 m over the plaza for 11
	# frames): the disc's move is pos += v, floor / wall clamp, then gravity (REACT.md class 1, 0x0C09D990 / d9bc), so
	# the body falls while the motion plays on, and lands on the floor below
	if grounded(): rx_fall = 0.0
	else:
		rx_fall -= GRAV_CM
		_core_move(Vector3(0, rx_fall, 0), false)
		if grounded(): rx_fall = 0.0
	rx_f0 -= 1
	if rx_f0 < 1:
		rx_tail = [[13, 175, 58] if stun == 0 else [24, 1000, int((_rx.get("measured", {}) as Dictionary).get("recover_24_frames", 8))]]
		_rx_begin_tail()

func _rx_launch() -> void:
	if rx_phase == "splat":
		_rx_splat(); return
	if rx_phase == "land":
		if rx_mrow >= _rx_len(rx_m): _rx_lie()
		return
	if rx_phase == "bounce":
		_rx_fly_move()
		if rx_v.y < 0.0 and grounded(): rx_phase = "settle"; rx_wait = 2
		return
	if rx_phase == "settle":   # landed: 2 more k2/115 rows on the floor, still sliding, then lying (40 of 40 logged)
		if rx_wait <= 0: _rx_lie(); return
		rx_wait -= 1
		_core_move(Vector3(rx_v.x, 0.0, rx_v.z), true)
		return
	# flying
	if rx_cls != 3 and rx_wait > 0: rx_wait -= 1
	elif rx_walls < 2 and _hit_wall() and (int(rx_rec[0x10]) & 1) == 0 and rx_cls != 3:
		rx_walls += 1
		var n := _wall_normal(); n.y = 0
		if n.length() > 0.01: facing = n.normalized(); _apply_facing()   # back to the wall
		global_position.y = maxf(global_position.y - 1.19, _floor_under())
		rx_v = Vector3.ZERO; rx_g = -1.0; rx_wait = 20
		rx_phase = "splat"; rx_cls = 22
		_rx_play(152)
		return
	rx_fr += 1
	if rx_cls == 3:
		if rx_v.y < 0.0 and grounded():
			# the bounce (657 logged rows): 11.6 up, gravity -2.97 already on its first row (8.63 up, then 8.63, 5.66 ...;
			# -0.97 was the disc's on-floor rows after it lands, mistaken for the bounce's), 9 rows to the floor
			rx_v.x *= 0.5; rx_v.z *= 0.5; rx_v.y = 11.6 + RX_BOUNCE_G; rx_g = RX_BOUNCE_G
			rx_phase = "bounce"; _rx_play(115)
			_core_move(rx_v, false)
			return
	elif rx_m0 in [96, 128]:
		if rx_ec == 0 and rx_fr >= _rx_len(rx_m0): _rx_play(rx_m0 + 1); rx_ec = 1
		elif rx_ec == 1 and rx_v.y < 0.0: _rx_play(rx_m0 + 2); rx_ec = 2
	if rx_cls != 3 and rx_v.y < 0.0 and grounded():
		rx_phase = "land"; _rx_play(131 if rx_side == 1 else 99)
		return
	_rx_fly_move()

func _rx_fly_move() -> void:
	var was_floor := grounded()
	_core_move(rx_v, was_floor and rx_v.y <= 0.0)
	rx_v.y += rx_g
	if grounded() and rx_v.y < 0.0 and rx_phase != "fly": rx_v.y = minf(rx_v.y, 0.0)

func _floor_under() -> float:   # the highest floor at or below the feet: the original's levels, else the stage mesh
	var best := -INF
	if arena:
		if arena.has_method("floor_levels"):
			for y in arena.floor_levels(global_position.x, global_position.z):
				if float(y) <= global_position.y + 0.05 and float(y) > best: best = float(y)
		if best == -INF and arena.has_method("ground_y"): best = arena.ground_y(global_position + Vector3.UP * 0.05)
	return best if best > -INF else global_position.y

func _rx_splat() -> void:
	if rx_wait > 0:
		rx_wait -= 1; return
	if rx_m == 152:
		if rx_v.y < 0.0 and grounded():
			_rx_play(153); return
		_core_move(Vector3(0, rx_v.y, 0), false)
		rx_v.y += rx_g
		return
	if rx_mrow >= int(((_rx.get("measured", {}) as Dictionary).get("len", {}) as Dictionary).get("153", 40)): _rx_lie()

func _rx_lie() -> void:
	var up := rx_side != 1
	if hp <= 0:   # the KO'd fighter stays lying: state 15 until the round flow's phase-5 pose sets 8 (fx-flow, logged)
		rx_tail = [[15, 144 if up else 145, 1 << 30]]
	else:
		var ly := 5
		rx_tail = [[15, 144 if up else 145, ly], [16, 146 if up else 147, 23], [16, 1000, 7]]
		if rx_dizzy: rx_tail.append([13, 175, 58])
	_rx_begin_tail()

func _rx_begin_tail() -> void:
	rx_phase = "tail"
	_rx_next_tail()

func _rx_next_tail() -> void:
	if rx_tail.is_empty():
		rx_on = false
		_gset(0, S.IDLE)
		return
	var t: Array = rx_tail[0]
	gst = int(t[0]); gst_t = 0
	_core_setting = true
	var coarse := {8: S.KO, 13: S.HITSTUN, 15: S.DOWN, 16: S.GETUP, 24: S.HITSTUN}.get(gst, S.HITSTUN) as int
	if hp <= 0: coarse = S.KO if gst in [8, 15] else S.DOWN
	if coarse != state: state = coarse; state_t = 0.0
	_core_setting = false
	_rx_play(int(t[1]))
	if gst == 16 and int(t[1]) == 1000: invuln = 0.0

func _rx_tail_tick() -> void:
	var t: Array = rx_tail[0]
	if not grounded(): _core_move(Vector3(0, -GRAV_CM * 4.0, 0), false)
	else: _core_move(Vector3.ZERO, true)
	t[2] = int(t[2]) - 1
	if int(t[2]) <= 0:
		rx_tail.pop_front()
		_rx_next_tail()


## --- core step 3c: grab-throws, per fighter as logged (game/assets/fidelity/throws.json, tools/throw_table.py from the
## o_moves_<id> tapes: every fighter grabs at the same row there). B next to the opponent = state 37 k1/84 for 11
## rows (the victim stops where he is), then the thrower's own k4 chain (Ryoma k4/7 82 rows, Falcon k4/0 91, Gunrock
## k4/3 > 4 > 5 ...) with its logged travel, the victim held in state 29 at the logged spot in front of him (150 cm;
## Kraken 180, Rouge 100) playing his k4 victim chain, the logged damage events (the game's formula on the fighter's
## throw total, split like the log; never recovered), then the release: the victim flies like a launch from the logged
## first-row velocity (e.g. Ryoma 22.2 cm/frame backward + 33.3 up, gravity -2) into the reaction machine's flight /
## wall splat / lying. Not ported: the k4 clips (not captured: the thrower holds k1/84's clip, the victim the hit clip),
## the grab's own reach / whiff (the remaster's 1.25 m test), throws of Final Valgas.
static var _throws := {}
var thr_on := false
var thr: Dictionary = {}
var thr_row := 0
var thr_seg := -1
var thr_vseg := -1
var thr_from := Vector3.ZERO
var thr_ang := 0.0
var thr_victim: Fighter = null
var thr_scale := 1.0
var held_by: Fighter = null

static func _throw_tables() -> void:
	if _throws.is_empty() and FileAccess.file_exists("res://assets/fidelity/throws.json"):
		_throws = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/throws.json"))

func _play_km(kind: int, mot: int, fallback: String) -> void:
	if kind == 0: _gplay(0, mot); return
	if kind == 2: _rx_play(mot); return
	if not (model is PSModel): return
	var pm := model as PSModel
	var c := _clip_prefix() + "k%d_%03d" % [kind, mot]
	var cm: Dictionary = pm.clipmap.get(pm.form, {})
	for n in cm:
		if str(cm[n]) == c:
			if pm.playing != n: pm.play(n)
			return
	if (pm.players.get(pm.form) as AnimationPlayer).has_animation(c): pm.play(c); return
	if fallback != "" and pm.has_clip(fallback) and pm.playing != fallback: pm.play(fallback)

func _seg_at(chain: Array, row: int) -> int:
	var cum := 0
	for i in chain.size():
		cum += int((chain[i] as Array)[3])
		if row < cum: return i
	return -1

func _core_grab(victim: Fighter) -> bool:
	_throw_tables()
	var t: Dictionary = _throws.get(char_id, {})
	if t.is_empty() or victim == null or victim.boss: return false
	thr = t; thr_on = true; thr_row = 0; thr_seg = -1; thr_vseg = -1
	var d := victim.global_position - global_position; d.y = 0
	if d.length() > 0.05: facing = d.normalized()
	thr_from = global_position; thr_ang = _ang(facing)
	thr_victim = victim
	victim.rx_on = false; victim.core_atk = false; victim.held_by = self
	if victim.carry: victim._drop_carry(true)
	var logged := 0
	for e in t.get("damage", []): logged += int(e[1])
	# the logged events are the game's own type-2 throw damage between two humans (no defence / combo / gem bonus):
	# Ryoma, Galuda, Valgas 60, the others 48; the formula adds what a CPU level or a Power Change changes
	var total := Rules.game_damage(logged, victim.defence(), 1, gems, powered, victim.powered, cpu_level, victim.cpu_level, 2)
	thr_scale = float(total) / float(maxi(1, logged))
	core_atk = false; rx_on = false
	_core_setting = true; state = S.GRAB; state_t = 0.0; _core_setting = false
	victim._core_setting = true; victim.state = S.DOWN; victim.state_t = 0.0; victim._core_setting = false
	grabbed = victim
	_throw_rows()
	_apply_facing()
	return true

func _throw_rows() -> void:   # this row's motions, positions and events for both fighters
	var ch: Array = thr.get("thrower", [])
	var i := _seg_at(ch, thr_row)
	if i < 0:
		_throw_end(); return
	if i != thr_seg:
		thr_seg = i
		var sg: Array = ch[i]
		gst = int(sg[0]); gst_t = 0
		_play_km(int(sg[1]), int(sg[2]), "grab")
	var tp: Array = thr.get("thrower_path", [])
	var f := _dir(thr_ang); var sd := Vector3(f.z, 0, -f.x)
	if thr_row < tp.size():
		var o: Array = tp[thr_row]
		global_position = thr_from + (f * float(o[0]) + Vector3.UP * float(o[1]) + sd * float(o[2])) * 0.01
		if arena: arena.clamp_fighter(self)
		if model is PSModel:   # fx-reach: the k4 clip's hip carries the same path (disc hip = clip hip - path: 0 cm median)
			(model as PSModel).travel_on = true
			(model as PSModel).travel_pin = -Vector3(float(o[2]), float(o[1]), float(o[0])) * 0.01
	var v := thr_victim
	if v == null or not is_instance_valid(v) or v.held_by != self: return
	var vc: Array = thr.get("victim", [])
	var j := _seg_at(vc, thr_row)
	if j >= 0 and j != thr_vseg:
		thr_vseg = j
		var vs: Array = vc[j]
		if int(vs[0]) == 29 or int(vs[0]) == 0:
			v.gst = 29 if int(vs[0]) == 29 else v.gst; v.gst_t = 0
			# the game plays the victim's k4 motion out of the THROWER's motion file on the victim's skeleton: captured
			# per pair as <victim prefix>k4_<id>_<thrower prefix> (tools/victim_clips.py, docs/CLIPS.md)
			if int(vs[1]) == 4 and v.model is PSModel and model is PSModel:
				var vm := v.model as PSModel
				var vc2 := v._clip_prefix() + "k4_%03d_%s" % [int(vs[2]), _clip_prefix()]
				if (vm.players.get(vm.form) as AnimationPlayer).has_animation(vc2): vm.play(vc2)
				else: v._play_km(int(vs[1]), int(vs[2]), "hit")
			else: v._play_km(int(vs[1]), int(vs[2]), "hit")
	var hf := int(thr.get("held_from", 11)); var held: Array = thr.get("held", [])
	if thr_row >= hf and thr_row - hf < held.size():
		var o: Array = held[thr_row - hf]
		v.global_position = global_position + (f * float(o[0]) + Vector3.UP * float(o[1]) + sd * float(o[2])) * 0.01
		if arena: arena.clamp_fighter(v)
		v.facing = -f; v._apply_facing()
	for e in thr.get("damage", []):
		if int(e[0]) == thr_row:
			var dmg := maxi(1, int(round(float(e[1]) * thr_scale)))
			v.hp = Rules.apply_damage(v.hp, dmg); v.rec_ceil = v.hp; v.rec_cnt = RECOVER_EVERY; v._rec_set_f = Engine.get_physics_frames(); v.last_hit_by = self   # a throw (type 2): nothing back
			v.damaged.emit(v, dmg)
			stats.dmg_dealt += dmg; stats.hits += 1
			if v.hp <= 0: v.knocked_out.emit(v)
	if thr_row == int(thr.get("release_row", -1)):
		var rv: Array = (thr.get("release_vel", [[0, 0]]) as Array)[0]
		var m0 := 117
		if j >= 0 and int((vc[j] as Array)[0]) == 27: m0 = int((vc[j] as Array)[2])
		v.held_by = null
		if arena and arena.drop_f >= 0:   # a throw launches: 1 gem toward the thrower (ITEMS.md 4; record byte 16 not read yet)
			var n := 1 if v.hp >= 0 and not v.powered and v.gems >= 1 and v.gems < Rules.GEMS_IN_PLAY else 0
			if n > 0:
				v.gems -= n; v.gem_count_changed.emit(v)
				arena.spill_from(v, global_position - v.global_position, n)
		else:
			var lost := Rules.gems_dropped(v.gems, true, powered, char_id == "valgas")
			if lost > 0:
				v.gems -= lost; v.gem_count_changed.emit(v)
				if arena: arena.spill_gems(v.global_position, lost)
		v.react_launch(f * float(rv[0]) + Vector3.UP * float(rv[1]), m0)
		stats.throws += 1

func _throw_tick() -> void:
	state_t += 1.0 / 60.0
	gst_t += 1
	thr_row += 1
	_throw_rows()

func _throw_end() -> void:
	thr_on = false; grabbed = null
	if thr_victim and is_instance_valid(thr_victim) and thr_victim.held_by == self:
		thr_victim.held_by = null; thr_victim.react_launch(Vector3.ZERO, 117)
	thr_victim = null
	_gset(0, S.IDLE)

## A thrower who is hit (or launched) mid-throw lets go: the throw no longer runs ahead of his reaction (it used to end in
## _throw_end's idle under a running reaction: a KO'd fighter stood up in Battle Royale, test_all ff61291 NOT-DOWN), and
## the victim falls from where he was held. The disc never logs it (two fighters: the only one who can hit him is held).
func _throw_cancel() -> void:
	if not thr_on: return
	thr_on = false; grabbed = null
	var v := thr_victim
	thr_victim = null
	if v and is_instance_valid(v) and v.held_by == self:
		v.held_by = null; v.react_launch(Vector3.ZERO, 117)

## Thrown (or released): a launch with a given velocity (cm/frame) and first motion, into the reaction machine's flight
func react_launch(v: Vector3, m0: int) -> void:
	_rx_tables()
	_throw_cancel()
	hitstop = 0.0
	rx_rec = PackedByteArray(); rx_rec.resize(20)
	rx_cls = 1; rx_on = true; rx_row = 2; rx_freeze = 0; rx_walls = 0; rx_tail = []; rx_dizzy = false; wk_t = -1
	rx_v = v; rx_g = -2.0; rx_m0 = m0; rx_ec = 0 if m0 in [96, 128] else 2; rx_fr = 0; rx_wait = 3; rx_side = 0
	rx_phase = "fly"
	core_atk = false; hit_stop = 0
	_core_setting = true
	state = S.DOWN if hp <= 0 else S.HITSTUN; state_t = 0.0
	_core_setting = false
	gst = 27; gst_t = 0
	_rx_play(m0)



## --- core step 4: the original's ground (Arena.core_ground, fx-proof: the stage's floors / walls / ledges measured in
## Flycast per stage, 1,307 of 1,320 probe drops within 2 cm, the run's step-up / hop / wall rules): the core moves the
## feet itself; the physics only pushes fighters off each other (horizontal, fighters' layer only). Ledges: a "step"
## holds the run LEDGE_HOLD_F frames, then the feet go up onto it; a "hop" holds HOP_HOLD_F + HOP_F frames (state 17's
## motion not captured); walls drop the velocity into them. clamp_fighter stays as the safety net.
const CORE_GROUND := true
var _grounded := true
var _ledge_hold := 0
var _climb := false
var _cg_wall := false
var _cg_normal := Vector3.ZERO

## The wall the last move ran into: the original's (core_ground: the area's edge / a ledge) or the remaster's collision
func _hit_wall() -> bool:
	return _cg_wall if _cg_on() else is_on_wall()

func _wall_normal() -> Vector3:
	return _cg_normal if _cg_on() else get_wall_normal()

func grounded() -> bool:
	return _grounded if _cg_on() else is_on_floor()

func _cg_on() -> bool:
	return CORE_GROUND and arena != null and is_inside_tree() and arena.has_method("core_ground") and arena.has_area()

func _core_move_cg(d: Vector3) -> void:
	var prev := global_position
	var mask := collision_mask
	collision_mask = 0   # nothing: the stage is the original's (below), bodies are pushed apart after the frame (body_push)
	velocity = Vector3(d.x, 0, d.z) * CM_S
	var snap := floor_snap_length
	floor_snap_length = 0.0
	move_and_slide()
	floor_snap_length = snap
	collision_mask = mask
	var feet := Vector3(global_position.x, prev.y + d.y * 0.01, global_position.z)
	var r: Dictionary = arena.core_ground(feet, prev, char_id, _climb, gst in [2, 31])
	_climb = false
	global_position = r.pos
	_grounded = bool(r.grounded)
	var k: String = str(r.get("ledge_kind", ""))
	if k == "step" or k == "hop":
		_ledge_hold += 1
		if _ledge_hold >= (Arena.LEDGE_HOLD_F if k == "step" else Arena.HOP_HOLD_F + Arena.HOP_F):
			_climb = true; _ledge_hold = 0
	else: _ledge_hold = 0
	_cg_wall = bool(r.wall); _cg_normal = r.normal
	if bool(r.wall):
		var n: Vector3 = r.normal
		var vd := vcm.dot(n)
		if vd < 0.0: vcm -= n * vd
	arena.clamp_fighter(self)
	velocity = vcm * CM_S
	_vel_out = velocity


## ---------------------------------------------------------------------------------------------------------------
## Items (fx-item2): the disc's weapons from the item chests (docs/ITEMS.md 5-7, BUG-46; the chests / items / shots
## live in Items, game/scripts/items.gd). Logged (items_weapon, items_id*, fxitem_id*; disc CPU logs for the lengths):
## B next to a ready floor item = state 35: when the item is 90 deg or more off the run heading, 5 rows first (the
## turn: the motion on display stays), then the family's pick-up motion 24 rows (25 with no turn; item 9 = the object
## carry k2/219 17 / 18); the item is in the hand from the pick-up motion's first row. Held: state 0 with the family's
## idle; the stick = state 2 with its walk at the move table's [3] (family 237) or [1] (the others; logged 7.0 / 4.6 for
## Ryoma) for at least 10 rows (a 3-row tap walked 10), family 195 (ids 3 / 4 / 5) runs instead (state 31 k2/203,
## stop state 32 k2/204 30 rows at 9.5 * (8 - k) / 7); jumps play the family's crouch / air / land. X or Y = state 10
## with the family's use motion (Items.USE: rows, shot / reach / thrown); used-up items leave the hand. A hit drops
## the held item (it falls from 180 cm up and rests where it lands). Power Change: the transform drops the item (2 of 2 disc CPU logs: a family-195 carry > k3/8 > k0/0). Not ported: uses in the air (pressing X / Y in the
## air does nothing while holding), the use motions' own travel, the item's own hit objects (Items.USE fits), Power
## Change with an item, the CPU's item goals (cpu_game.gd FIND_KIND6/7).
var item: Node3D = null                  # the held Items.Item
var item_react_rec := PackedByteArray()  # the item record of the hit being received (the reaction machine reads it)
var it_pre := 0
var it_len := 24
var _it_use := -1                        # the item id of the use in progress
var _it_walk_t := 0

func _items() -> Items:
	if arena == null or not ("items" in arena): return null
	return arena.get("items") as Items

func _it_fam() -> Array:
	return Items.family(int(item.id)) if item else []

## B with a ready floor item in reach (hook in _core_actions)
func _item_pickup() -> bool:
	var its := _items()
	if its == null or carry: return false
	var it := its.reach_item(self)
	if it == null: return false
	var d := it.global_position - global_position; d.y = 0
	var off := absf(_wrap(_ang(d) - head)) if d.length() > 0.01 else 0.0
	it_pre = 5 if off >= PI * 0.5 - 0.001 else 0
	var fam := Items.family(it.id)
	it_len = (17 if it_pre > 0 else 18) if int(fam[0]) == 219 else (24 if it_pre > 0 else 25)
	item = it
	if d.length() > 0.05: facing = d.normalized(); head = _ang(facing)
	_gset(35, S.IDLE)
	if it_pre == 0: its.take(it, self)
	else: it.sub = 5   # spoken for (nobody else takes it during the turn)
	_apply_facing()
	return true

## state 35 with an item (hook in the 35 transition)
func _item_pick_tick() -> void:
	if it_pre > 0 and gst_t == it_pre:
		_gplay(2, int(_it_fam()[0]))
		var its := _items()
		if its: its.take(item, self)
	if gst_t >= it_pre + it_len: _gset(0, S.IDLE)

## the family's motion for a core state while holding (hook in _gset); true = played
func _item_gplay(g: int) -> bool:
	var fam := _it_fam()
	if fam.is_empty(): return false
	var run := int(fam[0]) == 195
	match g:
		0: _gplay(2, int(fam[1]))
		2: _gplay(2, 202 if run else int(fam[2]))
		31: _gplay(2, (202 if _land_run > 0 else 203) if run else int(fam[2]))
		32: _gplay(2, 204 if run else int(fam[1]))
		4: _gplay(2, int(fam[3]))
		5, 14: _gplay(2, int(fam[4]))
		6: _gplay(2, int(fam[5]))
		35:
			if it_pre == 0: _gplay(2, int(fam[0]))
		_: return false
	return true

const IT_WALK_MIN := 10
const IT_STOP_LEN := 30
## velocity while holding (hook after the core's state handler): the walk, family 195's stop profile
func _item_vel(mv: Vector3, has_mv: bool) -> void:
	var fam := _it_fam()
	if fam.is_empty(): return
	if gst == 2 and int(fam[0]) != 195:
		if gst_t >= 1 and (has_mv or gst_t < IT_WALK_MIN):
			if has_mv: facing = mv.normalized(); head = _ang(facing)
			var sp := _mv(3) if int(fam[0]) == 237 else _mv(1)
			vcm.x = _dir(head).x * sp; vcm.z = _dir(head).z * sp
		else:
			vcm.x = 0.0; vcm.z = 0.0
	elif gst == 32 and int(fam[0]) == 195:
		var k := gst_t
		var sp := _mv(14) * (8.0 - k) / 7.0 if k >= 1 and k <= 7 else 0.0
		vcm.x = _dir(head).x * sp; vcm.z = _dir(head).z * sp

## ground transitions while holding (hook at the top of the 0 / 2 / 31 / 32 transitions); true = handled
func _item_ground(has_mv: bool, mv: Vector3) -> bool:
	var r := _item_ground_do(has_mv, mv)
	if r: _apply_facing()
	return r

func _item_ground_do(has_mv: bool, mv: Vector3) -> bool:
	if ic.is_pressed("punch") or ic.is_pressed("kick"):
		return _item_use_start()
	if ic.is_pressed("jump"): return false
	var fam := _it_fam()
	if int(fam[0]) == 195:   # runs like the plain fighter, its own stop length
		if gst == 32 and not has_mv and gst_t < IT_STOP_LEN: return true
		return false
	if gst in [0, 32, 31] and has_mv:
		facing = mv.normalized(); head = _ang(facing)
		_gset(2, S.RUN)
		return true
	if gst == 2:
		if has_mv or gst_t < IT_WALK_MIN: return true
		_gset(0, S.IDLE)
		return true
	return gst == 0

## X / Y while holding: state 10 with the family's use motion (the remaster has no hit steps for it: Items.USE)
func _item_use_start() -> bool:
	if item == null: return false
	var id := int(item.id)
	var u: Dictionary = Items.USE.get(id, {})
	if u.is_empty(): return false
	var um: Array = u.use
	gmo = "k%d_%03d" % [int(um[0]), int(um[1])]; gmo_f = 0; gmo_n = int(u.n) + 1; gmo_air = false; atk_open = 999   # n rows
	atk_ref = _ang(facing)
	cur_attack = "item"; attack_hit = false; _hit_mark = ""; _it_use = id
	core_atk = true
	_core_setting = true
	state = S.ATTACK; state_t = 0.0
	_core_setting = false
	gst = 10; gst_t = 0
	vcm = Vector3.ZERO
	item.sub = 14
	if model is PSModel:
		var pm := model as PSModel
		pm.root_motion = false
		var c := _clip_prefix() + gmo
		if (pm.players.get(pm.form) as AnimationPlayer).has_animation(c): pm.play(c)   # not captured: the motion on display stays
		pm.time_scale = 1.0
	_pbuf = {"X": 99, "Y": 99}
	return true

## every frame of a use (hook in _core_attack_tick, after gmo_f += 1)
func _item_use_tick() -> void:
	var its := _items()
	if its == null or _it_use < 0: return
	var u: Dictionary = Items.USE.get(_it_use, {})
	var tgt: Fighter = opponent
	if u.has("shot") and gmo_f == int((u.shot as Array)[0]):
		its.shoot(self, _it_use, tgt)
		if u.get("fly", false) and item:
			its.release(item, true); item = null
	if u.has("reach") and gmo_f == int((u.reach as Array)[0]) and tgt and Items.hittable(tgt):
		var d := tgt.global_position - global_position; d.y = 0
		if d.length() * 100.0 < float((u.reach as Array)[1]):
			its.apply_hit(self, tgt, int((Items.REC.get(_it_use, [8]) as Array)[0]), global_position)
			hit_stop = HITSTOP_ATK
	if gmo_f >= gmo_n - 1:
		if item:
			item.uses += 1
			item.sub = 5
			if u.has("uses") and item.uses >= int(u.uses): its.release(item, true); item = null
		_it_use = -1

## the held-time limit (ids 3 / 4: dropped 600 frames after the pick-up); called by Items every frame while held
func item_held_tick(held_t: int) -> void:
	if item == null: return
	var u: Dictionary = Items.USE.get(int(item.id), {})
	if u.has("hold") and held_t > int(u.hold) and gst in [0, 2, 31, 32]:
		item.expire = 51
		_item_drop()

## a hit (or the hold limit): the item falls out of the hand (hooks in receive_hit / react_start)
func _item_drop(refresh := true) -> void:
	var its := _items()
	var it := item
	item = null
	if its and it: its.release(it, false)
	if refresh and gst in [0, 2, 31, 32] and not core_atk: _gset(gst, state)
## ---------------------------------------------------------------------------------------------------------------
## Final Valgas (fx-fv2): his own fighter code, read out of 1ST_READ (sh4dis 0x0C08A6E4..0x0C08B7B4; docs/CPU.md
## "Final Valgas fighter port") and checked on the 8 disc rounds of fx-fv (tools/fv_fighter.py). He never walks, runs,
## jumps, grabs objects or gems. His AI (cpu_fv.gd) hands its pad words over (fv_pad / fv_prs = +0x2DC / +0x2E4) and
## this code answers them like his state handlers do: a press in state 0 / 2 = state 11 that frame with +0x7223 = the
## attack (0x200 -> 2, 0x410 -> 3, 0x004 -> 4, 0x014 -> 5, 0x404 -> 6, 0x204 -> 7, 0x400 -> 8: measured on the disc, 0x014
## never pressed there), the attack's own phases from the next frame (dispatcher 0x0C08A9A8 on +0x7223, phase byte +0x0A,
## timers +0xEC / +0xEE / +0xF0), never moving while it runs; the attacks pick their motion by the side the opponent is
## on (0x0C08A842: (angle to him - heading) & 0xFFFF < 0x8000). A direction = state 2: the heading turns 0.5 deg/frame
## toward the stick (k0/1 turning one way, k0/2 the other, picked on entry) and he glides 4 cm/frame along it while the
## stick is within 90 deg of it (else he turns in place); x / z clamped to +-950 cm on his arena (0x0C08A6E4). Hits
## only take health, except the first one under 100 and the first one at 50 or less each round: state 27 k2/0 for 60
## frames, then state 5 k0/6 (5 frames), then 0 (13 of 13 logged reactions; his KO = state 27 k2/0 through the KO call).
## k2/0 is not in his rig: Motion Check's k2/0 for him replays k2/118 frame for frame (an empty slot), so his reaction
## keeps the motion on display (no stand-in) until a real-fight capture of it exists.
## Not ported: his projectiles / beams (the effect objects 0x0C062210 / 0x0C0C9834 / 0x0C0CA268 carry most of his
## damage: the remaster's reach test stands in for them, see _fv_hits), the 0x600 throw (attacks 9 / 10: k4/2|3 grab
## beam > k4/0 > 4 | k4/1 > 5, 80 damage, the victim in state 29 k4/48 > 51 | k4/49 > 52), attack 1 (k1/0|1|14|15).
const FV_CORE := true
const FV_GLIDE_CM := 4.0          # every gliding frame of the 8 disc rounds: 3.99-4.01 cm/frame
const FV_TURN := PI / 360.0       # heading change while gliding: 0.496-0.503 deg/frame
const FV_GLIDE_MAX := PI / 2.0    # stick 105 deg off (log b f910): turned in place 119 frames; 70-88 deg off: glided
const FV_BOX_CM := 950.0
const FV_RX_F := 60
const FV_REC_F := 5
const FV_PADS := {0x200: 2, 0x410: 3, 0x004: 4, 0x014: 5, 0x404: 6, 0x204: 7, 0x400: 8}
## the remaster's attack row per motion for the reach test of the moves whose hits the disc's effect objects deliver
const FV_ROW := {"k1_096": "fusion2", "k1_097": "drive_k", "k1_098": "drive_k", "k1_104": "drive_k", "k1_099": "drive_p",
	"k1_100": "drive_p", "k1_101": "drive_p", "k1_103": "drive_p", "k1_102": "fusion1"}
## motion lengths (frames on display) when the clip is not in his rig: the disc logs
const FV_LEN := {"k2_000": 60, "k0_006": 5}
var fv_pad := 0                   # his AI's pad word this frame (+0x2DC)
var fv_prs := 0                   # pressed this frame (+0x2E4)
var fv_atk := 0                   # +0x7223
var fv_ph := 0                    # +0x0A
var fv_ec := 0                    # +0xEC
var fv_ee := 0                    # +0xEE
var fv_f0 := 0                    # +0xF0 (the second press)
var fv_m := ""                    # motion on display ("k1_097")
var fv_mf := 0                    # its frame (0 on the frame it is set)
var fv_mn := 0                    # frames it runs before the motion-end flag (+0x71AA): clip frames + 2 (logged)
var fv_h := 0.0                   # heading (+0x30, radians, game convention)
var fv_rx := 0                    # reactions had this round: 1 = under 100, 2 = 50 or less

func _fv_reset() -> void:
	fv_atk = 0; fv_ph = 0; fv_ec = 0; fv_ee = 0; fv_f0 = 0; fv_rx = 0; fv_m = ""; fv_mf = 0; fv_mn = 0
	fv_pad = 0; fv_prs = 0
	fv_h = _ang(facing); gst = 0; gst_t = 0

func _fv_on() -> bool:
	return FV_CORE and CORE and not OS.has_environment("PS_FV_OLD")

func _fv_rel() -> int:   # 0x0C08A8AA: (angle to the opponent - his heading) & 0xFFFF
	if opponent == null: return 0
	var d := opponent.global_position - global_position
	return (_u16(atan2(d.x, d.z)) - _u16(fv_h)) & 0xFFFF

func _fv_side() -> bool:   # 0x0C08A842
	return _fv_rel() < 0x8000

func _fv_set(g: int) -> void:
	var coarse: int = {0: S.IDLE, 2: S.RUN, 11: S.ATTACK, 27: S.HITSTUN, 5: S.HITSTUN}.get(g, S.IDLE)
	if g == 27 and hp <= 0: coarse = S.KO
	gst = g; gst_t = 0
	if coarse != state:
		_core_setting = true
		state = coarse; state_t = 0.0
		_core_setting = false
	if model is PSModel: (model as PSModel).root_motion = false

func _fv_play(kind: int, mot: int) -> void:
	fv_m = "k%d_%03d" % [kind, mot]; fv_mf = 0
	fv_mn = int(FV_LEN.get(fv_m, 60))
	if model is PSModel:
		var pm := model as PSModel
		var ap: AnimationPlayer = pm.players.get(pm.form)
		var c := _clip_prefix() + fv_m
		if ap and ap.has_animation(c): fv_mn = int(round(ap.get_animation(c).length * 60.0)) + 2
		pm.time_scale = 1.0
	cur_attack = str(FV_ROW.get(fv_m, "kick1" if mot in [2, 3, 16, 17] else "punch1"))
	attack_hit = false; _hit_mark = ""
	_gplay(kind, mot)
	var sh = _fv_shots()
	if sh and kind == 1: sh.begin(fv_m); sh.spawn(0)

func _fv_end() -> bool:   # +0x71AA
	return fv_mf >= fv_mn

## Every frame instead of the shared tick (true = handled)
func _fv_tick() -> bool:
	if not _fv_on(): return false
	state_t += 1.0 / 60.0
	invuln = maxf(0.0, invuln - 1.0 / 60.0)
	gst_t += 1; fv_mf += 1
	hitstop = 0.0
	var sh = _fv_shots()
	if sh: sh.tick()   # his live shots move one row and test, before his own frame (fx-shot's order)
	if gst in [0, 2, 5, 11, 27]:
		# 0x0C08A6E4: the second presses, before the state handler
		if gst == 11 and fv_atk == 6 and fv_f0 == 0 and fv_ph == 2 and fv_ee == 0 and (fv_prs & 4) != 0 and (fv_pad & 0x400) != 0:
			fv_ph = 3; fv_f0 = 1
		elif gst == 11 and fv_atk == 4 and fv_f0 == 0 and fv_ec != 0 and fv_ph == 1 and (fv_prs & 4) != 0:
			fv_f0 = 1
		match gst:
			0, 2: _fv_free()
			11: _fv_attack()
			27:
				if hp > 0 and gst_t >= FV_RX_F:
					_fv_set(5); _fv_play(0, 6)
			5:
				if gst_t >= FV_REC_F: _fv_set(0); _fv_play(0, 0)
	var d := Vector3.ZERO
	if gst == 2 and gst_t > 0 and absf(_fv_stick_off()) < FV_GLIDE_MAX: d = _dir(fv_h) * FV_GLIDE_CM
	var on_floor := grounded()
	if not on_floor: vcm.y -= GRAV_CM
	else: vcm.y = 0.0
	d.y = vcm.y
	vcm = Vector3(d.x, vcm.y, d.z)
	_core_move(d, on_floor)
	if arena and str(arena.get("stage")) == "stga0":   # 0x0C08A6E4: his arena's box
		global_position.x = clampf(global_position.x, -FV_BOX_CM * 0.01, FV_BOX_CM * 0.01)
		global_position.z = clampf(global_position.z, -FV_BOX_CM * 0.01, FV_BOX_CM * 0.01)
	facing = _dir(fv_h)
	_apply_facing()
	return true

var _fv_s := 0.0   # the stick's world angle this frame (state 2)
func _fv_stick_off() -> float: return _wrap(_fv_s - fv_h)

## State 0 / 2 (no handler of his own in the attack table): a press starts an attack, a direction turns / glides
func _fv_free() -> void:
	if fv_prs != 0 and FV_PADS.has(fv_prs):
		fv_atk = int(FV_PADS[fv_prs]); fv_ph = 0; fv_ec = 0; fv_ee = 0; fv_f0 = 0
		_fv_set(11)
		return
	if fv_pad & 0xF0 == 0:
		if gst != 0: _fv_set(0); _fv_play(0, 0)
		return
	var mx := float((fv_pad & 0x80) != 0) - float((fv_pad & 0x40) != 0)
	var my := float((fv_pad & 0x20) != 0) - float((fv_pad & 0x10) != 0)
	var v := cam_basis * Vector3(mx, 0, my)
	_fv_s = atan2(v.x, v.z)
	var off := _fv_stick_off()
	if gst != 2:
		_fv_set(2); _fv_play(0, 1 if off < 0.0 else 2)
	fv_h = _wrap(fv_h + clampf(off, -FV_TURN, FV_TURN))

## State 11: the attack by +0x7223 / phase (each phase as his handler; "end" = 0x0C0980B0, back to state 0)
func _fv_attack() -> void:
	match fv_atk:
		2:   # 0x0C08AD68: k1/97 30 frames > k1/98 (rnd 3 + 1) x 30 > k1/104 to its end
			match fv_ph:
				0: fv_ph = 1; fv_ec = 30; _fv_play(1, 97)
				1:
					fv_ec -= 1
					if fv_ec == 0:
						fv_ph = 2; fv_ec = (CPUGame.rnd(3) + 1) * 30; fv_ee = 1; _fv_play(1, 98)
				2:
					fv_ee -= 1
					if fv_ee == 0: fv_ee = 30; CPUGame.rnd(6)   # (a shot of 0x0C0CA268 every 30 frames: not ported)
					fv_ec -= 1
					if fv_ec == 0: fv_ph = 3; _fv_play(1, 104)
				3:
					if _fv_end(): fv_ph = 4
				_: _fv_done()
		3:   # 0x0C08AF2C: k1/6 | 10 (opponent on the left) > k1/9 | 13 (-1 / -2 by how far off the heading he is)
			match fv_ph:
				0:
					fv_ph = 1; fv_ec = 1 if _fv_side() else 0; _fv_play(1, 10 if fv_ec != 0 else 6)
				1:
					if _fv_end():
						fv_ph = 2
						var r := _fv_rel()
						var m := 13 if fv_ec != 0 else 9
						if ((r + 0x08E3) & 0xFFFF) > 0x1000:
							m -= 1 if ((r + 0x1000) & 0xFFFF) >= 0x2000 else 2
						_fv_play(1, m)
				2:
					if _fv_end(): fv_ph = 3
				_: _fv_done()
		4:   # 0x0C08B08C: k1/3 (left) | 2, a second 0x004 in the first 45 | 40 frames = k1/17 | 16 at that frame count
			match fv_ph:
				0:
					fv_ph = 1; fv_ee = 1 if _fv_side() else 0
					fv_ec = 45 if fv_ee != 0 else 40; fv_f0 = 0; _fv_play(1, 3 if fv_ee != 0 else 2)
				1:
					fv_ec -= 1
					if fv_ec == 0 and fv_f0 != 0:
						fv_ph = 2; _fv_play(1, 17 if fv_ee != 0 else 16)
					elif _fv_end(): fv_ph = 3
				2:
					if _fv_end(): fv_ph = 3
				_: _fv_done()
		5:   # 0x0C08B1A6: k1/5 (left) | 4 > k1/17 | 16
			match fv_ph:
				0: fv_ph = 1; fv_ee = 1 if _fv_side() else 0; _fv_play(1, 5 if fv_ee != 0 else 4)
				1:
					if _fv_end(): fv_ph = 2; _fv_play(1, 17 if fv_ee != 0 else 16)
				2:
					if _fv_end(): fv_ph = 3
				_: _fv_done()
		6:   # 0x0C08B4BE: k1/99 > k1/100 (46 frames for a second 0x404: k1/101 (left) | 103, or 100 again within 10 deg)
			match fv_ph:
				0: fv_ph = 1; _fv_play(1, 99)
				1:
					if _fv_end(): fv_ph = 2; _fv_play(1, 100); fv_ec = 46; fv_ee = 0; fv_f0 = 0
				2:
					fv_ec -= 1
					if fv_ec == 0 and fv_ee == 0: fv_ee = 1
					if _fv_end(): fv_ph = 5
				3:
					fv_ec = 46; fv_ph = 2
					if ((_fv_rel() + 0x071C) & 0xFFFF) <= 0x0E38: _fv_play(1, 100)
					else: _fv_play(1, 101 if _fv_side() else 103)
				_: _fv_done()
		7:   # 0x0C08B6B0: k1/102 to its end
			match fv_ph:
				0: fv_ph = 1; _fv_play(1, 102)
				1:
					if _fv_end(): fv_ph = 2
				_: _fv_done()
		8:   # 0x0C08B7B4: k1/96 to its end
			match fv_ph:
				0: fv_ph = 1; _fv_play(1, 96)
				1:
					if _fv_end(): fv_ph = 2
				_: _fv_done()
		_: _fv_done()
	var sh = _fv_shots()
	if sh and gst == 11 and fv_mf > 0 and fv_m.begins_with("k1"): sh.spawn(fv_mf)   # the shots that start on this row
	if gst == 11: _fv_hits()

func _fv_done() -> void:   # 0x0C0980B0
	fv_atk = 0; fv_ph = 0
	_fv_set(0); _fv_play(0, 0)

## His hits: the game's own spheres and frames where his hit data has them (k1/2 3 6-17 96 98 99 102), else the
## remaster's reach test over the move row's window scaled to the motion (stand-in for his effect objects)
func _fv_hits() -> void:
	if fv_m == "" or not fv_m.begins_with("k1"): return
	if _game_hit_update(): return
	if _fv_sh != null and _fv_sh.has_shots(char_id, fv_m): return   # his shots carry this motion's hits (no reach test)
	var a: Dictionary = Rules.ATTACKS.get(cur_attack, Rules.ATTACKS.punch1)
	var k := float(fv_mn) / (float(a.t2) * 60.0)
	var t := float(fv_mf) / 60.0
	if not attack_hit and t >= float(a.t0) * k and t <= float(a.t1) * k: _check_hit(a)

## receive_hit's boss branch: health only, except the round's first hit under 100 / at 50 or less and the KO
func _fv_hit() -> void:
	hitstop = 0.0
	facing = _dir(fv_h); _apply_facing()   # his heading does not turn toward the attacker
	if hp <= 0:
		fv_atk = 0; fv_ph = 0
		_fv_set(27); _fv_play(2, 0)
		knocked_out.emit(self)
		return
	var react := false
	if hp < 100 and (fv_rx & 1) == 0:
		fv_rx |= 1; react = true
	elif hp <= 50 and (fv_rx & 2) == 0:
		fv_rx |= 2; react = true
	if react:
		fv_atk = 0; fv_ph = 0
		_fv_set(27); _fv_play(2, 0)

## His shots (fx-fv2 data: game/assets/fidelity/fv_shots.json, tools/fv_shots.py, keyed by his motion) run on fx-shot's
## PCShots (scripts/pc_shots.gd + Fighter.shot_land / shot_hit, branch fx-shot) once both are on the branch: loaded by
## path so this file compiles without them; until then null (the reach test of _fv_hits stands in).
var _fv_sh = null
static var _fv_sh_tab := false

func _fv_shots():
	if _fv_sh != null: return _fv_sh
	if not has_method("shot_land") or not ResourceLoader.exists("res://scripts/pc_shots.gd") \
			or not FileAccess.file_exists("res://assets/fidelity/fv_shots.json"): return null
	var C = load("res://scripts/pc_shots.gd")
	if not _fv_sh_tab:   # his table joins fx-shot's in place (its static _t: fighters[char][move] = {shots: [...]})
		C._load()
		var t = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/fv_shots.json"))
		var tab: Dictionary = C._t
		if not tab.has("fighters"): tab["fighters"] = {}
		(tab["fighters"] as Dictionary)[char_id] = ((t as Dictionary).get("fighters", {}) as Dictionary).get(char_id, {})
		_fv_sh_tab = true
	_fv_sh = C.new(self)
	return _fv_sh
