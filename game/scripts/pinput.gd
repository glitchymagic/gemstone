class_name PInput
extends RefCounted
## One player's controls for this frame. Humans poll keyboard + pad, the CPU writes the fields.
## Layout follows the Dreamcast pad by position (SPEC s1): DC X = punch, Y = kick, A = jump,
## B = action (punch+kick: pick up / grab), L/R = Power Fusion. On a PS5 pad that is
## Square = punch, Triangle = kick, Cross = jump, Circle = action, L1/L2 and R1/R2 = Fusion.

var move := Vector2.ZERO   # x right, y down (screen space); the fight turns it camera-relative
var held := {}
var pressed := {}
var _prev := {}

const BUTTONS := ["punch", "kick", "jump", "action", "fusion1", "fusion2", "start"]
const KB := [
	{"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S, "punch": KEY_J, "kick": KEY_K, "jump": KEY_SPACE,
	 "action": KEY_L, "fusion1": KEY_U, "fusion2": KEY_I, "start": KEY_ENTER},
	{"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN, "punch": KEY_KP_1, "kick": KEY_KP_2,
	 "jump": KEY_KP_0, "action": KEY_KP_3, "fusion1": KEY_KP_4, "fusion2": KEY_KP_5, "start": KEY_KP_ENTER},
]
const PAD := {"punch": [JOY_BUTTON_X], "kick": [JOY_BUTTON_Y], "jump": [JOY_BUTTON_A], "action": [JOY_BUTTON_B],
	"fusion1": [JOY_BUTTON_LEFT_SHOULDER], "fusion2": [JOY_BUTTON_RIGHT_SHOULDER], "start": [JOY_BUTTON_START]}

func _init() -> void:
	for b in BUTTONS:
		held[b] = false; pressed[b] = false; _prev[b] = false

func is_pressed(b: String) -> bool:
	return pressed.get(b, false)

func is_held(b: String) -> bool:
	return held.get(b, false)

## Human: keyboard scheme `kb` (0/1, -1 none) and joypad `pad` (-1 none).
func poll_human(kb: int, pad: int) -> void:
	var m := Vector2.ZERO
	var now := {}
	for b in BUTTONS: now[b] = false
	if kb >= 0:
		var k: Dictionary = KB[kb]
		m.x = float(Input.is_physical_key_pressed(k.right)) - float(Input.is_physical_key_pressed(k.left))
		m.y = float(Input.is_physical_key_pressed(k.down)) - float(Input.is_physical_key_pressed(k.up))
		for b in BUTTONS: now[b] = Input.is_physical_key_pressed(k[b])
	if pad >= 0:
		var stick := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if stick.length() > 0.22: m += stick
		m.x += float(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT))
		m.y += float(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP))
		for b in PAD:
			for jb in PAD[b]:
				if Input.is_joy_button_pressed(pad, jb): now[b] = true
		if Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT) > 0.5: now.fusion1 = true
		if Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > 0.5: now.fusion2 = true
	set_state(m.limit_length(1.0), now)

## Shared by humans and the CPU: edge-detects presses.
func set_state(m: Vector2, now: Dictionary) -> void:
	move = m
	for b in BUTTONS:
		var h: bool = now.get(b, false)
		pressed[b] = h and not _prev[b]
		held[b] = h
		_prev[b] = h
