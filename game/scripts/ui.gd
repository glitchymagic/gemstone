class_name UI
extends RefCounted
## Menus built in code: title, character select, results, pause, options. PS5 glyphs are drawn
## as shapes (square / triangle / cross / circle) so they don't depend on a font.

static func glyph(c: Control, kind: String, pos: Vector2, r := 12.0) -> void:
	var col: Color = {"square": Color(0.95, 0.5, 0.8), "triangle": Color(0.3, 0.9, 0.7),
		"cross": Color(0.5, 0.7, 1.0), "circle": Color(1.0, 0.4, 0.4)}.get(kind, Color.WHITE)
	c.draw_circle(pos, r + 5, Color(0.08, 0.08, 0.1))
	match kind:
		"square": c.draw_rect(Rect2(pos - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), col, false, 2.5)
		"triangle":
			var p := PackedVector2Array([pos + Vector2(0, -r * 0.7), pos + Vector2(r * 0.7, r * 0.5), pos + Vector2(-r * 0.7, r * 0.5), pos + Vector2(0, -r * 0.7)])
			c.draw_polyline(p, col, 2.5)
		"cross":
			c.draw_line(pos + Vector2(-r, -r) * 0.6, pos + Vector2(r, r) * 0.6, col, 2.5)
			c.draw_line(pos + Vector2(r, -r) * 0.6, pos + Vector2(-r, r) * 0.6, col, 2.5)
		"circle": c.draw_arc(pos, r * 0.65, 0, TAU, 24, col, 2.5)

static func game() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")

static func label(text: String, size: int, col := Color.WHITE) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0))
	l.add_theme_constant_override("outline_size", maxi(4, size / 10))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func button(text: String, cb: Callable) -> Button:
	var b := Button.new(); b.text = text
	b.add_theme_font_size_override("font_size", 34)
	b.custom_minimum_size = Vector2(420, 64)
	b.pressed.connect(cb)
	return b

## Start toggles the pause like the original's: the pad's Start or Escape close the menu again (Enter / Cross press
## the focused button). docs/HUNT.md H-4.
class PauseKeys extends Node:
	var fight: Fight
	func _unhandled_input(e: InputEvent) -> void:
		var close: bool = (e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE) or \
			(e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START)
		if close and fight and is_instance_valid(fight) and fight.get_tree().paused:
			get_viewport().set_input_as_handled()
			fight._pause(false)

static func pause_menu(fight: Fight) -> Control:
	var root := ColorRect.new(); root.color = Color(0, 0, 0, 0.6)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	root.add_child(v)
	v.add_child(label("PAUSE", 80, Color(1, 0.85, 0.3)))
	var r := button("Resume", func(): fight._pause(false))
	v.add_child(r)
	v.add_child(button("Quit to title", func():
		fight.get_tree().paused = false
		game().goto_title()))
	v.position = Vector2(-210, -160)
	r.call_deferred("grab_focus")
	var keys := PauseKeys.new(); keys.fight = fight; root.add_child(keys)
	return root
