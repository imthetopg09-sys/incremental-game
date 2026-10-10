shader_type canvas_item;

// Pixel-space position of the lantern and the size of the drawn rect.
uniform vec2 light_pos = vec2(640.0, 360.0);
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform float radius = 220.0;
uniform float intensity = 1.0;
uniform vec3 light_color : source_color = vec3(1.0, 0.68, 0.32);
uniform vec3 night_color : source_color = vec3(0.012, 0.012, 0.024);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Offset-row cobblestones: returns 0 in the mortar gaps, ~1 on a stone.
float cobbles(vec2 p) {
	vec2 cell_size = vec2(46.0, 30.0);
	float row = floor(p.y / cell_size.y);
	p.x += mod(row, 2.0) * cell_size.x * 0.5;
	vec2 cell = floor(p / cell_size);
	// Distance in pixels from this point to the nearest edge of its stone.
	vec2 local = (fract(p / cell_size) - 0.5) * cell_size;
	vec2 to_edge = cell_size * 0.5 - abs(local);
	float edge_px = min(to_edge.x, to_edge.y);
	float stone = smoothstep(1.5, 4.5, edge_px);
	return stone * mix(0.55, 1.0, hash(cell));
}

void fragment() {
	vec2 p = UV * rect_size;
	float d = length(p - light_pos);
	float flicker = 0.94 + 0.04 * sin(TIME * 13.0) + 0.02 * sin(TIME * 31.0 + 1.7);
	float r = radius * flicker * intensity;
	float glow = exp(-(d * d) / (r * r));
	float halo = exp(-d / (r * 2.6)) * 0.12;
	vec3 ground = mix(vec3(0.10, 0.09, 0.11), vec3(0.32, 0.27, 0.24), cobbles(p));
	vec3 col = night_color + ground * light_color * glow + light_color * halo * intensity;
	COLOR = vec4(col, 1.0);
}
