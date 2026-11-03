extends RefCounted
## Remix lighting, headless: Original untouched, storm (sky, wet stage shader, rain + splashes, lightning), night with
## the stage's own lamps found in its textures + snow on Mutsu/Oedo, indoor stages get no rain, quality tiers.

static func run(t: SceneTree) -> void:
	print("== remix lighting")
	var ck := func(c: bool, w: String): t.call("check", c, w)
	var n0 := Node3D.new(); var a0 := Arena.new()   # never in the tree: freed by hand (they leaked at exit)
	ck.call(Remix.apply(n0, a0, "original") == null, "Original = no remix (the default look)")
	a0.free(); n0.free()
	var root := Node3D.new(); t.root.add_child(root)
	Look.build_environment(root, 2)
	var a := Arena.new(); a.stage = "stg00"; root.add_child(a); a.build(1)
	var r := Remix.apply(root, a, "storm", 2)
	var env := (root.get_node("Look") as WorldEnvironment).environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	ck.call(r != null and sky.sky_top_color.v < 0.2 and (root.get_node("Sun") as DirectionalLight3D).light_energy < 0.5, "storm: dark sky, the sun behind clouds")
	var shaded := 0; var wet := 0.0
	for mi in Mats._meshes(a):
		var m := (mi as MeshInstance3D).get_surface_override_material(0)
		if m is ShaderMaterial and String((m as ShaderMaterial).shader.resource_path).contains("remix_stage"):
			shaded += 1; wet = maxf(wet, float((m as ShaderMaterial).get_shader_parameter("wet")))
	ck.call(shaded > 10 and wet == 1.0, "stage on the remix shader, wet (%d surfaces)" % shaded)
	ck.call(r.rain != null and r.rain.amount == Remix.RAIN[2] and r.splash != null, "rain + splashes at the High tier")
	for i in 60 * 14: r._process(1.0 / 60.0)
	ck.call(r.bolts >= 1, "lightning strikes (%d in 14 s)" % r.bolts)
	root.queue_free()
	var root2 := Node3D.new(); t.root.add_child(root2)
	Look.build_environment(root2, 0)
	var a2 := Arena.new(); a2.stage = "stg60"; root2.add_child(a2); a2.build(1)
	var r2 := Remix.apply(root2, a2, "night", 0)
	ck.call(r2.snow != null and r2.rain == null, "night on Oedo: snow")
	ck.call(r2.lamps.size() > 0 and r2.lamps.size() <= Remix.LAMPS[0] and r2.lamps.all(func(l): return not l.shadow_enabled), "the stage's own lamps found in its textures (%d of %d spots, Low tier: no lamp shadows)" % [r2.lamps.size(), r2.lamp_spots.size()])
	root2.queue_free()
	var root3 := Node3D.new(); t.root.add_child(root3)
	Look.build_environment(root3, 2)
	var a3 := Arena.new(); a3.stage = "stg20"; root3.add_child(a3); a3.build(1)
	Look.stage_tweak(root3, a3.info)
	var r3 := Remix.apply(root3, a3, "storm", 2)
	ck.call(r3.rain == null and r3.bolt != null, "indoor stage (Wang-Tang's dojo): lightning, no rain indoors")
	root3.queue_free()
	# the remix on top of the Remaster look (pass 6 materials, sky and exposure)
	var prev := HD.force_look
	HD.force_look = "remaster"
	var root4 := Node3D.new(); t.root.add_child(root4)
	Look.build_environment(root4, 2)
	var a4 := Arena.new(); a4.stage = "stg00"; root4.add_child(a4); a4.build(1)
	Look.stage_tweak(root4, a4.info)
	HD.stage(root4, a4)
	var we4 := root4.get_node("Look") as WorldEnvironment
	Remix.apply(root4, a4, "storm", 2)
	var pbr := 0; var wet4 := 0.0
	for mi in Mats._meshes(a4):
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_surface_override_material(s)
			if m is ShaderMaterial and String((m as ShaderMaterial).shader.resource_path).contains("stage_pbr"):
				pbr += 1; wet4 = maxf(wet4, float((m as ShaderMaterial).get_shader_parameter("wet")))
	ck.call(pbr > 10 and wet4 == 1.0, "Remaster + storm: the stage's PBR surfaces get wet (%d surfaces)" % pbr)
	var hs := we4.environment.sky.sky_material
	ck.call(hs is ShaderMaterial and ((hs as ShaderMaterial).get_shader_parameter("top_color") as Color).v < 0.2 and we4.environment.background_mode == Environment.BG_SKY, "Remaster + storm: dark HD sky, the game's day plane hidden")
	ck.call(we4.camera_attributes == null or not (we4.camera_attributes as CameraAttributesPractical).auto_exposure_enabled, "Remaster + storm: auto exposure off (it would lift the dark back up)")
	root4.queue_free()
	HD.force_look = prev
