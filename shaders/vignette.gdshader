shader_type canvas_item;

// Cheap screen vignette + film grain. No extra render passes.

uniform float strength : hint_range(0.0, 1.0) = 0.6;
uniform vec3 tint : source_color = vec3(0.01, 0.015, 0.02);
uniform float grain : hint_range(0.0, 0.15) = 0.035;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float dist = distance(uv, vec2(0.5, 0.52));
	float vignette = smoothstep(0.32, 0.92, dist) * (strength + pulse * 0.25);
	float noise = fract(sin(dot(uv * vec2(913.0, 717.0) + TIME * 0.35, vec2(12.9898, 78.233))) * 43758.5453);
	float alpha = clamp(vignette + noise * grain, 0.0, 1.0);
	COLOR = vec4(tint, alpha);
}
