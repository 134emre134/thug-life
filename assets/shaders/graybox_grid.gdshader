// World-space grid for gray-box geometry: 1 m cells with a heavier line
// every `major_every` cells, so distances and speeds are easy to read.
shader_type spatial;
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.55);
uniform vec3 line_color : source_color = vec3(0.38);
uniform float cell_size = 1.0;
uniform float line_width = 0.02;
uniform float major_every = 5.0;
uniform float roughness = 0.9;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p, float cell, float width) {
	vec2 d = abs(fract(p / cell - 0.5) - 0.5) * cell;
	vec2 fw = fwidth(p);
	vec2 l = 1.0 - smoothstep(vec2(width) - fw, vec2(width) + fw, d);
	return max(l.x, l.y);
}

float grid_layers(vec2 p) {
	return max(grid(p, cell_size, line_width) * 0.6, grid(p, cell_size * major_every, line_width * 1.5));
}

void fragment() {
	vec3 n = abs(world_normal);
	float l;
	if (n.x > n.y && n.x > n.z) {
		l = grid_layers(world_pos.zy);
	} else if (n.y > n.z) {
		l = grid_layers(world_pos.xz);
	} else {
		l = grid_layers(world_pos.xy);
	}
	ALBEDO = mix(base_color, line_color, l);
	ROUGHNESS = roughness;
}
