class_name Gem
extends Node3D
## A Power Stone. Body = the disc's gem mesh + facet texture (common model bank in 1ST_READ.BIN,
## part 67, textures from EFKY_MODEL.BIN), tinted per stone like the original.

const COLORS := [Color(1.0, 0.25, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2)]
var vel := Vector3.ZERO
var age := 0.0
var color_idx := 0
var visual: Node3D

func _ready() -> void:
	var path := "res://assets/ripped/gem.glb"
	if ResourceLoader.exists(path):
		visual = (load(path) as PackedScene).instantiate()
		visual.scale = Vector3.ONE * 0.01 * 1.6
		add_child(visual)
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS[color_idx]
		var src := Mats._meshes(visual)
		if src.size() > 0:
			var sm := (src[0] as MeshInstance3D).get_active_material(0)
			if sm is BaseMaterial3D: m.albedo_texture = (sm as BaseMaterial3D).albedo_texture
		m.metallic = 0.3; m.roughness = 0.08
		m.emission_enabled = true; m.emission = COLORS[color_idx]; m.emission_energy_multiplier = 1.6
		m.rim_enabled = true
		for mi in Mats._meshes(visual):
			for s in (mi as MeshInstance3D).mesh.get_surface_count(): (mi as MeshInstance3D).set_surface_override_material(s, m)
		var l := OmniLight3D.new(); l.light_color = COLORS[color_idx]; l.omni_range = 2.5; l.light_energy = 1.2
		add_child(l)

## The disc's gem (docs/ITEMS.md 1-4, fx-item; checked on the disc logs): a SPOT gem (one of the stage's 3 drop spots)
## sits frozen 0.09 m over the spot for 121 frames, hops (vy 0.20 m/f, g 0.012 m/f^2) and rests 0.50 m over the floor,
## takeable from frame 130; a SPILLED gem (knocked out on a hit) flies 0.20 m/f + vy 0.30 from 1 m up and 1 m toward
## the attacker, a wall reverses that axis at half speed, it stops 0.50 m over the floor, takeable from frame 40. With no
## fighter's feet within 3 m it blinks after 900 frames and is gone at 990, its colour queued for the next drop.
const SPOT_FROZEN_F := 121
const HOP_VY := 0.20
const GEM_G := 0.012
const REST_UP := 0.50
const TAKE_SPOT_F := 130
const TAKE_SPILL_F := 40
const UNATT_R := 3.0
const BLINK_AT := 900
const GONE_AT := 990
var spot := -1                # drop spot index, -1 = spilled
var t := 0                    # frames since it appeared
var unattended := 0
var resting := false
var legacy := false           # Battle Royale / old path: the remaster's own fall

func takeable() -> bool:
	return t >= (TAKE_SPOT_F if spot >= 0 else TAKE_SPILL_F) if not legacy else age >= 0.6

func tick(dt: float, arena: Arena) -> void:
	age += dt
	if legacy:
		_tick_legacy(dt, arena); return
	t += 1
	var p := global_position
	if spot >= 0 and t <= SPOT_FROZEN_F:
		pass
	elif not resting:
		if spot >= 0 and t == SPOT_FROZEN_F + 1: vel = Vector3(0, HOP_VY, 0)
		var q := p + vel
		if arena.has_area():   # the original's walls round the area: that axis back at half speed
			if not arena.inside(q.x, p.z, 0.0): vel.x *= -0.5; q.x = p.x + vel.x
			if not arena.inside(q.x, q.z, 0.0): vel.z *= -0.5; q.z = p.z + vel.z
		vel.y -= GEM_G
		var fy := arena.floor_y_at(q.x, q.z, p.y + 0.3, 0.3) if arena.has_area() else arena.ground_y(q)
		if fy <= -INF: fy = arena.ground_y(q)
		if vel.y < 0.0 and q.y <= fy + REST_UP:
			q.y = fy + REST_UP; vel = Vector3.ZERO; resting = true
		p = q
	global_position = p
	var near := false
	for f in arena.fighters:
		if f.global_position.distance_to(p) < UNATT_R: near = true; break
	unattended = 0 if near else unattended + 1
	if visual: visual.visible = unattended < BLINK_AT or (unattended / 4) % 2 == 0
	if visual: visual.rotation.y += dt * 2.5

func gone() -> bool:
	return not legacy and unattended >= GONE_AT

func _tick_legacy(dt: float, arena: Arena) -> void:
	var g := arena.ground_y(global_position) + 0.45
	if global_position.y > g or vel.y > 0:
		vel.y -= 20.0 * dt
		global_position += vel * dt
		if global_position.y < g:
			global_position.y = g; vel = Vector3.ZERO
	var p := global_position
	if not arena.inside(p.x, p.z, 0.3): p = arena.clamp_point(p, 0.3)   # the original's playable area (arena.gd)
	if arena.stage == "stg00" and Vector2(p.x, p.z).length() < Arena.FOUNTAIN_R and p.y < 1.0:
		p += Vector3(p.x, 0, p.z).normalized() * 0.1
	global_position = p
	if visual: visual.rotation.y += dt * 2.5
