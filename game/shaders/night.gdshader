shader_type canvas_item;

// Up to MAX_LIGHTS lights in pixel space: xy = position, z = radius, w = intensity.
const int MAX_LIGHTS = 16;
uniform vec4 lights[MAX_LIGHTS];
uniform vec4 light_colors[MAX_LIGHTS];
uniform int light_count = 0;
uniform vec2 rect_size = vec2(1280.0, 720.0);
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
	vec3 ground = mix(vec3(0.10, 0.09, 0.11), vec3(0.32, 0.27, 0.24), cobbles(p));
	vec3 col = night_color;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) {
			break;
		}
		vec4 L = lights[i];
		float d = length(p - L.xy);
		float glow = exp(-(d * d) / (L.z * L.z));
		float halo = exp(-d / (L.z * 2.6)) * 0.12;
		col += (ground * glow + halo) * light_colors[i].rgb * L.w;
	}
	COLOR = vec4(col, 1.0);
}
