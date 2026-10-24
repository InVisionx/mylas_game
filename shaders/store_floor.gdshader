shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Cheap tiled lino floor. Two tints + speckle, all procedural: no textures.
uniform vec3 color_a : source_color = vec3(0.74, 0.75, 0.72);
uniform vec3 color_b : source_color = vec3(0.66, 0.67, 0.64);
uniform float tile_size = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_pos.xz / tile_size);
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 base = mix(color_a, color_b, checker);

	float grain = fract(sin(dot(floor(world_pos.xz * 22.0), vec2(12.9898, 78.233))) * 43758.5453);
	base *= 0.95 + grain * 0.05;

	// Faint dirt gathering against the shelf lines.
	float wear = smoothstep(0.35, 1.0, abs(fract(world_pos.x * 0.5) - 0.5));
	base *= 1.0 - wear * 0.04;

	ALBEDO = base;
	ROUGHNESS = 0.38;
	SPECULAR = 0.32;
}
