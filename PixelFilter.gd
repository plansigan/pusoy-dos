# PixelFilter.gd
# Autoload CanvasLayer that pixelates everything drawn beneath it,
# Balatro-style: chunky pixel blocks plus faint scanlines.
#
# The chunky frame is BLENDED over the crisp frame (strength uniform) —
# that blend is what keeps text readable while still looking retro.
# Presets are exposed in the settings menu via apply_level();
# Settings.pixel_level persists the choice.

extends CanvasLayer

const SHADER_CODE = "
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float pixel_size : hint_range(1.0, 8.0) = 2.0;
uniform float strength : hint_range(0.0, 1.0) = 0.5;
uniform float scanline_strength : hint_range(0.0, 0.5) = 0.04;

void fragment() {
	vec4 crisp = texture(screen_texture, SCREEN_UV);
	vec2 block = SCREEN_PIXEL_SIZE * pixel_size;
	vec2 uv = block * (floor(SCREEN_UV / block) + 0.5);
	vec4 chunky = texture(screen_texture, uv);
	float line = mod(floor(SCREEN_UV.y / block.y), 2.0);
	chunky.rgb *= 1.0 - scanline_strength * line;
	COLOR = mix(crisp, chunky, strength);
}
"

const LEVEL_NAMES = ["OFF", "LIGHT", "MEDIUM", "HEAVY"]
const LEVEL_PARAMS = [
	{},  # OFF — filter hidden entirely
	{"pixel_size": 2.0, "strength": 0.5, "scanlines": 0.04},
	{"pixel_size": 2.0, "strength": 0.8, "scanlines": 0.06},
	{"pixel_size": 3.0, "strength": 1.0, "scanlines": 0.08},
]

var rect: ColorRect

func _ready() -> void:
	layer = 100
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader = Shader.new()
	shader.code = SHADER_CODE
	var mat = ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	add_child(rect)
	apply_level(Settings.pixel_level)


# 0 = off, 1 = light, 2 = medium, 3 = heavy
func apply_level(level: int) -> void:
	level = clampi(level, 0, LEVEL_PARAMS.size() - 1)
	rect.visible = level > 0
	if level == 0:
		return
	var params = LEVEL_PARAMS[level]
	var mat = rect.material as ShaderMaterial
	mat.set_shader_parameter("pixel_size", params["pixel_size"])
	mat.set_shader_parameter("strength", params["strength"])
	mat.set_shader_parameter("scanline_strength", params["scanlines"])


# Fine-grained knobs, should you ever want values between the presets
func set_enabled(value: bool) -> void:
	rect.visible = value

func set_pixel_size(value: float) -> void:
	(rect.material as ShaderMaterial).set_shader_parameter("pixel_size", value)

func set_strength(value: float) -> void:
	(rect.material as ShaderMaterial).set_shader_parameter("strength", value)

func set_scanlines(value: float) -> void:
	(rect.material as ShaderMaterial).set_shader_parameter("scanline_strength", value)
