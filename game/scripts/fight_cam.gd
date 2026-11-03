class_name FightCam
extends RefCounted
## The fight camera. Base = the original's camera, read out of its camera object in RAM (0x0C7F2664) every frame of
## long CPU-vs-CPU logs on every stage (tools/stagelog.py -> tools/cam_stage.py -> game/assets/fidelity/STG_cam.json;
## docs/fx-cam.md). The rule, per 60 Hz frame:
## - target: the fighters' FEET midpoint + 1 m; the camera looks at a smoothed copy S: x/z close 1/8 of the gap, y in
##   whole-cm steps of 1/8 of the gap (truncated: S.y rests up to 7 cm off);
## - yaw: one of three presets 20 deg apart per stage (Londo -155/-135/-115), picked by where S is on the stage (zone
##   grid; "keep" cells = the original's hysteresis), eased 10% of the gap per frame;
## - distance: horizontal eye distance follows max(dmin, a + sqrt((b*across)^2 + (c*along)^2 + (e*height gap)^2)) of
##   the fighters' separation, rising / falling at k_out / k_in of the gap per frame with a dead band;
## - eye height: min(5 m world height, S.y + 0.279 x distance), eased 5% per frame; 41.1 deg vertical FOV.
## Stages without a fidelity file: stgN0_info.json cam_zones / cam_levels (Londo, 2026-10-23) or one yaw per stage.
## On top, what the remaster's wider 16:9 frame and HUD need (each a documented deviation, docs/fx-cam.md):
## - both fighters whole on screen and under the HUD: aim higher, then dolly back (fighters on stairs, poles, jumps);
## - never behind a wall: when the stage's own geometry is between the lens and a fighter or fills the frame right in
##   front of the lens, swing round it from the original's preset (yaw steps up to 48 deg), then pull in / crane up;
##   back once that view is clear;
## - stage objects in the way fade (scripts/scenery_fade.gd); a fighter right at the lens turns see-through.

const FOLLOW := 0.135
const HIP := 1.05           # hip height over the feet (the game's fighter position is its hip)
const EYE_UP := 2.6
const EYE_MAX := 5.0
const SAFE_TOP := 0.135     # below the HUD (names, health, timer: hud.gd)
const SAFE_BOT := 0.96
const SAFE_X := 0.04
const HEAD := 0.12          # margin above the head sphere (hair)
const SWING := [0.21, -0.21, 0.42, -0.42, 0.63, -0.63, 0.84, -0.84, 1.05, -1.05]   # 12 deg steps (up to 60: Jack's room wall)
const PULL := [0.82, 0.66]
const LIFT := [1.2, 2.4, 3.6]

var fight: Fight
var tgt := Vector3.ZERO
var extra := 0.0            # fit: extra distance (smoothed)
var aim := 0.0              # fit: aim raised by (m, smoothed)
var yaw_off := 0.0          # wall avoidance (smoothed) ...
var pull := 1.0
var lift := 0.0
var want := [0.0, 1.0, 0.0] # ... and its goal [yaw, pull, lift]
var back_t := 0.0           # how long the stage's own view has been clear while swung away
var fade := SceneryFade.new()
var yaw := 0.0              # live yaw (fighters' controls follow it)
var base_yaw := 0.0         # the original's preset for where the fight is (Londo: by area), eased
var zone_want := 0.0
var zone_hold := 0.0
var zones := {}             # stgN0_info.json cam_zones (the original's yaw preset per area)
var levels := {}            # stgN0_info.json cam_levels (the original's stepped zoom)
var level := -1
var dist_s := 0.0           # smoothed distance
var brawl_up := -1.0         # Battle Royale: eye height over the target grows with the spread (-1 = 1v1 rule)
var fid := {}               # game/assets/fidelity/STG_cam.json: the original's camera on this stage, measured
var hd := 0.0               # the original's rule: horizontal eye distance (m) ...
var eye_y := 0.0            # ... eye height (m, world)
var want_i := -1            # ... the preset it turns to (index into fid.yaws_deg)
var cand_i := -1
var cand_n := 0
var base := {}              # the pure rule this frame (tests/cam_replay.gd: the fidelity numbers)

func setup(f: Fight) -> void:
	fight = f
	fade.setup(f.arena)
	zones = f.arena.info.get("cam_zones", {})
	levels = f.arena.info.get("cam_levels", {})
	indoor = bool(f.arena.info.get("indoor", false))
	base_yaw = f.cam_yaw; zone_want = f.cam_yaw; yaw = f.cam_yaw
	var p := "res://assets/fidelity/%s_cam.json" % f.arena.stage
	if FileAccess.file_exists(p): fid = JSON.parse_string(FileAccess.get_file_as_string(p))

## Godot yaw (the eye sits at Basis(UP, yaw) * -Z from the target) of the original's yaw (eye direction atan2(x, z))
static func godot_yaw(deg: float) -> float:
	return deg_to_rad(deg - 180.0)

## The original's preset index for the aim point p (fid zone grid), -1 = keep the current one
func _fid_zone(p: Vector3) -> int:
	var z: Dictionary = fid.zones
	var c := float(z.cell_cm) * 0.01
	var col := clampi(int(floor((p.x - float(z.x0_cm) * 0.01) / c)), 0, int(z.cols) - 1)
	var row := clampi(int(floor((p.z - float(z.z0_cm) * 0.01) / c)), 0, int(z.rows) - 1)
	return int(z.grid[row][col])

## Final Valgas's arena: the original's other camera (tools/cam_stage.py sim_boss()): it aims 2 m over the boss's feet,
## the eye stays on the far side of the player along the boss -> player line, its distance grows with their separation
## and its height with the player's height over the boss's feet.
func _rule_boss(dt: float) -> void:
	var n := dt * 60.0
	var B: Dictionary = fid.boss
	var fs := fight.fighters
	var boss: Fighter = fs[1]
	for x in fs: if (x as Fighter).boss: boss = x
	var pl: Fighter = fs[0] if boss == fs[1] else fs[1]
	var bp := boss.global_position; var pp := pl.global_position
	var want_t := bp + Vector3.UP * float(B.aim_y_cm) * 0.01   # (the boss stands at y 0 in the original)
	var dv := pp - bp; dv.y = 0
	var yw := godot_yaw(rad_to_deg(atan2(dv.x, dv.z))) if dv.length() > 0.01 else base_yaw
	var dist := (float(B.dist_a) + float(B.dist_b) * dv.length() * 100.0) * 0.01
	var h := bp.y + (float(B.eye_a) + float(B.eye_b) * (pp.y - bp.y) * 100.0) * 0.01
	if tgt == Vector3.ZERO:
		tgt = want_t; base_yaw = yw; hd = dist; eye_y = h
	else:
		tgt += (want_t - tgt) * (1.0 - pow(1.0 - float(B.aim_ease), n))
		base_yaw = lerp_angle(base_yaw, yw, 1.0 - pow(1.0 - float(B.yaw_ease), n))
		hd += (dist - hd) * (1.0 - pow(1.0 - float(B.dist_ease), n))
		eye_y += (h - eye_y) * (1.0 - pow(1.0 - float(B.eye_ease), n))
	zone_want = base_yaw
	base = {"yaw": base_yaw, "hd": hd, "eye_y": eye_y, "tgt": tgt}

## One frame of the original's rule (tools/cam_stage.py sim() is the same code in Python): tgt, base_yaw, hd, eye_y.
func _rule(a: Vector3, b: Vector3, dt: float) -> void:
	var n := dt * 60.0
	var want_t := (a + b) * 0.5 + Vector3.UP * float(fid.get("target_up_cm", 100.0)) * 0.01
	var yaws: Array = fid.yaws_deg
	var D: Dictionary = fid.dist
	var first := tgt == Vector3.ZERO
	if first:
		tgt = want_t
	else:
		var k := 1.0 - pow(1.0 - float(fid.get("target_ease", 0.125)), n)
		tgt.x += (want_t.x - tgt.x) * k; tgt.z += (want_t.z - tgt.z) * k
		tgt.y += float(int((want_t.y - tgt.y) * 100.0 * k)) * 0.01   # whole cm, truncated like the original
	var zi := _fid_zone(want_t if str(fid.zones.get("of", "")).begins_with("target T") else tgt)
	if want_i < 0:
		want_i = zi
		if want_i < 0:   # a "keep" cell at the very start: the preset nearest the stage's own yaw
			var best := 1e9
			for i in yaws.size():
				var dd := absf(angle_difference(godot_yaw(float(yaws[i])), fight.cam_yaw))
				if dd < best: best = dd; want_i = i
	if zi >= 0 and zi != want_i:
		cand_n = cand_n + 1 if zi == cand_i else 1
		cand_i = zi
		if cand_n > int(fid.zones.get("hold_frames", 0)): want_i = zi; cand_n = 0
	else: cand_n = 0
	var yw := godot_yaw(float(yaws[want_i]))
	base_yaw = yw if first else lerp_angle(base_yaw, yw, 1.0 - pow(1.0 - float(fid.get("yaw_ease", 0.1)), n))
	zone_want = yw
	var back := Basis(Vector3.UP, base_yaw) * Vector3(0, 0, -1)
	var right := Vector3(back.z, 0, -back.x)
	var dv := (a - b) * 100.0
	var dy := absf(dv.y); dv.y = 0
	var lat := absf(dv.dot(right)); var dep := absf(dv.dot(back))
	var req := maxf(float(D.dmin), float(D.a) + sqrt(pow(float(D.b) * lat, 2) + pow(float(D.c) * dep, 2) + pow(float(D.e) * dy, 2))) * 0.01
	var band := float(D.band) * 0.01
	if first or hd <= 0.0: hd = req
	elif req > hd: hd += (req - hd) * (1.0 - pow(1.0 - float(D.k_out), n))
	elif req < hd - band: hd += (req + band - hd) * (1.0 - pow(1.0 - float(D.k_in), n))
	var h := minf(float(fid.eye_cap_cm) * 0.01, tgt.y + float(fid.eye_k) * hd)
	eye_y = h if first else eye_y + (h - eye_y) * (1.0 - pow(1.0 - float(fid.get("eye_ease", 0.05)), n))
	base = {"yaw": base_yaw, "hd": hd, "eye_y": eye_y, "tgt": tgt}

## Godot yaw of the original's preset for an aim point (cam_zones grid; the stage's one preset elsewhere)
func _zone_yaw(p: Vector3) -> float:
	if zones.is_empty(): return fight.cam_yaw
	var c := float(zones.cell_cm) * 0.01
	var col := clampi(int(floor((p.x - float(zones.x0_cm) * 0.01) / c)), 0, int(zones.cols) - 1)
	var row := clampi(int(floor((p.z - float(zones.z0_cm) * 0.01) / c)), 0, int(zones.rows) - 1)
	var i := int(zones.grid[row][col])
	return deg_to_rad(float(zones.yaws_deg[i]) - 180.0)

## [feet point, top point, hip point] per fighter still in the frame's business
func _bodies(of: Array = []) -> Array:
	var out := []
	var fs: Array = of if not of.is_empty() else fight.fighters
	if fs.size() > 2:
		var live := fs.filter(func(x): return x.hp > 0)
		if live.size() >= 2: fs = live
	for f in fs:
		var fi := f as Fighter
		var top := fi.global_position.y + 0.5
		var ext := []   # every body sphere's top and bottom (a fighter lying toward the lens reaches lower on screen)
		var sph := []   # the upper part of every body sphere: where the body really is (a fighter lying / getting up
						# stretches 1.7 m along the floor, away from its feet point)
		for s in CamCheck.body(fi):
			var c: Vector3 = s[0]; var r: float = s[1]
			top = maxf(top, c.y + r)
			ext += [c + Vector3.UP * r, c - Vector3.UP * r]
			sph.append([c, r])
		var p := fi.global_position
		out.append([p, Vector3(p.x, top + HEAD, p.z), p + Vector3.UP * minf(1.0, (top - p.y) * 0.55), ext, sph])
	return out

func update(dt: float) -> void:
	var cam := fight.cam
	var fs: Array = fight.cam_targets() if fight.has_method("cam_targets") else fight.fighters   # fx-flow: the winner alone on his win spot
	var a: Vector3 = fs[0].global_position; var b: Vector3 = fs[1].global_position
	if not fid.is_empty() and fs.size() == 2:
		if str(fid.get("mode", "")) == "boss": _rule_boss(dt)
		else: _rule(a, b, dt)
		_finish(cam, hd, dt)
		return
	var want_t := (a + b) * 0.5 + Vector3.UP * HIP
	var k := 1.0 - pow(1.0 - FOLLOW, dt * 60.0)
	# the original's yaw preset for this part of the stage: switch once the aim has been in the new area for 0.25 s,
	# ease over ~33 frames like the game
	var zy := _zone_yaw(want_t)
	if absf(angle_difference(zy, zone_want)) > 0.01:
		zone_hold += dt
		if zone_hold > 0.25: zone_want = zy; zone_hold = 0.0
	else: zone_hold = 0.0
	base_yaw = lerp_angle(base_yaw, zone_want, 1.0 - pow(1.0 - 0.09, dt * 60.0))
	var base_back := Basis(Vector3.UP, base_yaw) * Vector3(0, 0, -1)
	var right := Vector3(base_back.z, 0, -base_back.x)
	var dv := a - b; dv.y = 0
	var across := absf(dv.dot(right)); var along := absf(dv.dot(base_back))
	if fs.size() > 2:   # Battle Royale: the same rule on the box around everyone still standing
		var pts := fs.filter(func(f): return f.hp > 0).map(func(f): return f.global_position)
		if pts.size() < 2: pts = fs.map(func(f): return f.global_position)
		var lo := Vector2(1e9, 1e9); var hi := Vector2(-1e9, -1e9); var ylo := 1e9; var yhi := -1e9
		for p in pts:
			var q := Vector2(p.dot(right), p.dot(base_back))
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y)); hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
			ylo = minf(ylo, p.y); yhi = maxf(yhi, p.y)
		across = hi.x - lo.x; along = hi.y - lo.y
		var mid := (lo + hi) * 0.5
		want_t = right * mid.x + base_back * mid.y + Vector3.UP * ((ylo + yhi) * 0.5 + HIP)
		along += 1.6 * (yhi - ylo)
		brawl_up = minf(EYE_UP + 0.3 * along, 7.0)
	tgt = want_t if tgt == Vector3.ZERO else tgt.lerp(want_t, k)
	var dist := 4.57 + 0.42 * across + 0.90 * along
	if not levels.is_empty() and fs.size() == 2:   # the original's stepped zoom (with 40 cm of hysteresis)
		var sep := Vector2(dv.x, dv.z).length() * 100.0
		var cuts: Array = levels.sep_cm
		var want_l := 0
		for c in cuts: if sep > float(c): want_l += 1
		if level < 0: level = want_l
		elif want_l > level and sep > float(cuts[level]) + 40.0: level = want_l
		elif want_l < level and sep < float(cuts[level - 1]) - 40.0: level = want_l
		dist = float(levels.dist_cm[level]) * 0.01
	if fs.size() > 2: dist += 0.25 * maxf(across, along)
	dist_s = dist if dist_s == 0.0 else lerpf(dist_s, dist, 1.0 - pow(1.0 - 0.06, dt * 60.0))
	_finish(cam, dist_s, dt)

## The remaster's deviations on top of the base camera (aim point tgt, yaw base_yaw, distance dist): fit, walls, eye.
func _finish(cam: Camera3D, dist: float, dt: float) -> void:
	var bodies := _bodies()
	# 1) fit: aim up / dolly back until every fighter is whole between the HUD and the bottom edge
	var fit := _fit(tgt, dist, bodies, cam.fov)
	var up_k := 1.0 - pow(1.0 - 0.22, dt * 60.0); var dn_k := 1.0 - pow(1.0 - 0.035, dt * 60.0)
	aim = lerpf(aim, fit.x, up_k if fit.x > aim else dn_k)
	extra = lerpf(extra, fit.y, up_k if fit.y > extra else dn_k)
	# 2) walls: keep the goal while its view is clear; when blocked, the nearest clear swing / pull / lift
	var pts := []
	sph_sets = []
	for bd in bodies:
		pts += [bd[1] - Vector3.UP * 0.15, bd[2], bd[0] + Vector3.UP * 0.25]
		sph_sets.append(bd[4])
	var look := tgt + Vector3.UP * aim
	if not _clear(_eye(tgt, aim, dist + extra, want), look, pts):
		want = _search(look, dist + extra, pts)
		back_t = 0.0
	elif want != [0.0, 1.0, 0.0]:
		back_t = back_t + dt if _clear(_eye(tgt, aim, dist + extra, [0.0, 1.0, 0.0]), look, pts) else 0.0
		if back_t > 0.6: want = [0.0, 1.0, 0.0]; back_t = 0.0
	# ease to the goal; while the view from where the camera is now hides a fighter, three times as fast (the 8% ease
	# took ~30 frames to clear a body lying behind a wall: most of the in-game hidden frames)
	var rate := 0.08
	if want != [0.0, 1.0, 0.0] and not _clear(_eye(tgt, aim, dist + extra, [yaw_off, pull, lift]), look, pts): rate = 0.24
	var sk := 1.0 - pow(1.0 - rate, dt * 60.0)
	yaw_off = lerpf(yaw_off, float(want[0]), sk)
	pull = lerpf(pull, float(want[1]), sk)
	lift = lerpf(lift, float(want[2]), sk)
	yaw = base_yaw + yaw_off
	var eye := _eye(tgt, aim, dist + extra, [yaw_off, pull, lift])
	cam.global_position = eye   # built from smoothed values (aim, distance, yaw, fit): no second lag on top
	if fight.fx: cam.global_position += fight.fx.shake_offset()
	cam.look_at(look, Vector3.UP)

## After the cinematics had their say on the camera: fade what's in the way of the fighters, and a fighter right in
## front of the lens (a cinematic circling one fighter passes close to the other).
var _ghost := {}
func post(dt: float) -> void:
	post_for(fight.fighters, fight.cam, dt)

## The same for any set of fighters and camera: the replay theater runs it on the recorded camera, so replays and
## highlight renders fade the same objects the live fight did (fade.setup(arena) first; `fight` isn't used).
func post_for(fighters: Array, c: Camera3D, dt: float) -> void:
	for f in fighters:
		var fi := f as Fighter
		if fi.model == null: continue
		var d := c.global_position.distance_to(fi.global_position + Vector3.UP * 1.0)
		var g: float = _ghost.get(fi, 0.0)
		var w := 1.0 if d < 1.15 else 0.0
		var g2 := move_toward(g, w, dt * (8.0 if w > g else 3.0))
		if g2 != g:
			_ghost[fi] = g2
			for m in Mats._meshes(fi.model): (m as GeometryInstance3D).transparency = smoothstep(0.0, 1.0, g2) * 0.75
	var pts := []
	var near := 1e9
	for bd in _bodies(fighters):
		var p0: Vector3 = bd[0]; var top: Vector3 = bd[1]
		for u in [0.05, 0.3, 0.55, 0.8, 0.97]: pts.append(p0.lerp(top, u))
		for sp in bd[4]: pts.append((sp[0] as Vector3) + Vector3.UP * float(sp[1]) * 0.6)   # the body itself (lying / getting up: away from the feet point)
		near = minf(near, c.global_position.distance_to(bd[2]))
	fade.update(c, pts, near, dt)

## Eye for the aim t (the original's height rule for this stage), the aim raised by aim_m (the eye rises half as
## much), distance d, and a wall-avoidance choice w = [yaw offset, pull factor, lift].
func _eye(t: Vector3, aim_m: float, d: float, w: Array) -> Vector3:
	var back := Basis(Vector3.UP, base_yaw + float(w[0])) * Vector3(0, 0, -1)
	var e := t + back * d * float(w[1])
	var h: float
	if brawl_up >= 0.0: h = t.y + brawl_up
	elif not fid.is_empty() and fight.fighters.size() == 2:
		# the original's eye height for its distance; a fit dolly / wall pull keeps the original's pitch, never
		# lifting the eye past the 5 m cap on its own
		var more := d * float(w[1]) - hd
		h = eye_y + more * float(fid.get("eye_k", 0.279))
		if more > 0.0: h = minf(h, maxf(float(fid.get("eye_cap_cm", 500.0)) * 0.01, eye_y))
	elif not levels.is_empty():
		h = minf(t.y + float(levels.eye_k) * d, maxf(float(levels.eye_cap_cm) * 0.01, t.y + 1.0))
	else: h = minf(t.y + EYE_UP, maxf(EYE_MAX + HIP, t.y + 1.0))
	e.y = h + aim_m * 0.5 + float(w[2])
	return e

## Every point visible from the eye past the stage's own geometry (placed objects don't count: they fade), the eye
## itself not inside or against a wall, and no wall filling the frame right in front of the lens.
func _clear(eye: Vector3, look: Vector3, pts: Array) -> bool:
	var space := fight.get_world_3d().direct_space_state
	var ex := [fight.arena.scenery_body.get_rid()] if fight.arena.scenery_body else []
	var q := PhysicsRayQueryParameters3D.create(look, eye + (eye - look).normalized() * 0.5, 1, ex)
	if space.intersect_ray(q): return false
	for p in pts:
		var r := PhysicsRayQueryParameters3D.create(eye, p, 1, ex)
		if space.intersect_ray(r): return false
	for ss in sph_sets:   # SPH_HIDDEN or more of a fighter's body spheres behind the stage's geometry = hidden
		var n := 0
		for sp in ss:
			var c: Vector3 = sp[0]
			var p := c - (c - eye).normalized() * float(sp[1])   # the sphere's near side, as CamCheck.occluded
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, p, 1, ex)):
				n += 1
				if n >= SPH_HIDDEN: return false
	if _clutter(eye, look, space, ex) > CLUTTER: return false
	return not indoor or _void(eye, look, space) <= VOID

var sph_sets: Array = []   # per fighter, its body spheres' test points this frame (_bodies)
const SPH_HIDDEN := 3      # of 11 body spheres (CamCheck/cam_audit call a fighter hidden at 30%)
const VOID := 0.08   # indoor stages: most of the frame allowed to show the empty outside of the building
var indoor := false  # stgN0_info.json "indoor" (Wang-Tang's dojo): the 16:9 frame is wider than the original's 4:3,
					 # so from the original's camera spot its sides look past the walls into nothing

## Fraction of an 8x5 grid of view rays that hit nothing at all within 60 m.
func _void(eye: Vector3, look: Vector3, space: PhysicsDirectSpaceState3D) -> float:
	var f := (look - eye).normalized(); var r := f.cross(Vector3.UP).normalized(); var u := r.cross(f)
	var tv := tan(deg_to_rad(fight.cam.fov) * 0.5); var th := tv * 16.0 / 9.0
	var n := 0
	for gy in 5:
		for gx in 8:
			var d := (f + r * th * lerpf(-0.95, 0.95, gx / 7.0) + u * tv * lerpf(0.92, -0.92, gy / 4.0)).normalized()
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + d * 60.0, 1)): n += 1
	return n / 40.0

const CLUTTER := 0.06   # most of the frame a wall may cover within NEAR_WALL of the lens
const NEAR_WALL := 2.6

## Fraction of an 8x5 grid of view rays that hit the stage's own geometry within NEAR_WALL m of the lens.
func _clutter(eye: Vector3, look: Vector3, space: PhysicsDirectSpaceState3D, ex: Array) -> float:
	var lim := minf(NEAR_WALL, eye.distance_to(look) - 1.5)
	if lim <= 0.3: return 0.0
	var f := (look - eye).normalized(); var r := f.cross(Vector3.UP).normalized(); var u := r.cross(f)
	var tv := tan(deg_to_rad(fight.cam.fov) * 0.5); var th := tv * 16.0 / 9.0
	var n := 0
	for gy in 5:
		for gx in 8:
			var d := (f + r * th * lerpf(-0.92, 0.92, gx / 7.0) + u * tv * lerpf(0.9, -0.9, gy / 4.0)).normalized()
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + d * lim, 1, ex)): n += 1
	return n / 40.0

func _search(look: Vector3, d: float, pts: Array) -> Array:
	var cands := []
	for s in SWING: cands.append([s, 1.0, 0.0])
	for p in PULL:
		for s in [0.0, 0.21, -0.21, 0.42, -0.42]: cands.append([s, p, 0.0])
	for l in LIFT:
		for s in [0.0, 0.21, -0.21, 0.42, -0.42]: cands.append([s, 1.0, l])
	# nearest to where the camera is now first
	cands.sort_custom(func(x, y): return _cost(x) < _cost(y))
	for c in cands:
		if _clear(_eye(tgt, aim, d, c), look, pts): return c
	return [0.0, 1.0, 0.0]

func _cost(c: Array) -> float:
	return absf(float(c[0]) - yaw_off) * 2.0 + absf(float(c[0])) + (1.0 - float(c[1])) * 4.0 + float(c[2]) * 0.6

## [aim up (m), extra distance (m)] so every body's top and feet sit inside the safe frame.
func _fit(t: Vector3, d: float, bodies: Array, fov: float) -> Vector2:
	var tv := tan(deg_to_rad(fov) * 0.5)
	var asp := 16.0 / 9.0
	var vp := fight.cam.get_viewport() if fight.cam.is_inside_tree() else null
	if vp: asp = vp.get_visible_rect().size.aspect()
	var up_m := 0.0; var ex := 0.0
	for it in 40:
		var look := t + Vector3.UP * up_m
		var e := _eye(t, up_m, d + ex, [yaw_off, 1.0, 0.0])
		var f := (look - e).normalized(); var r := f.cross(Vector3.UP).normalized(); var u := r.cross(f)
		var ymin := 1e9; var ymax := -1e9; var xmin := 1e9; var xmax := -1e9
		for bd in bodies:
			for p in [bd[0], bd[1], bd[2] + r * 0.45, bd[2] - r * 0.45] + bd[3]:
				var v: Vector3 = p - e
				var z := maxf(v.dot(f), 0.2)
				var sy := 0.5 - v.dot(u) / (z * 2.0 * tv)
				var sx := 0.5 + v.dot(r) / (z * 2.0 * tv * asp)
				ymin = minf(ymin, sy); ymax = maxf(ymax, sy); xmin = minf(xmin, sx); xmax = maxf(xmax, sx)
		var fits_y := ymax - ymin <= SAFE_BOT - SAFE_TOP
		if ymin >= SAFE_TOP and ymax <= SAFE_BOT and xmin >= SAFE_X and xmax <= 1.0 - SAFE_X: break
		if fits_y and ymin < SAFE_TOP and ymax + (SAFE_TOP - ymin) <= SAFE_BOT:
			up_m += (SAFE_TOP - ymin) * 2.0 * tv * (d + ex) * 0.9 + 0.02   # re-aim up
		else:
			ex += 0.25
	return Vector2(up_m, ex)
