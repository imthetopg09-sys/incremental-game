shader_type canvas_item;

// Up to MAX_LIGHTS lights in pixel space: xy = position, z = radius, w = intensity.
// The radius is the light's real reach: the pool has a visible edge there, with a
// soft spill beyond it for atmosphere.
const int MAX_LIGHTS = 16;
uniform vec4 lights[MAX_LIGHTS];
uniform vec4 light_colors[MAX_LIGHTS];
uniform int light_count = 0;
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform vec3 night_color : source_color = vec3(0.02, 0.02, 0.032);
// A little light everywhere so black shadows read as silhouettes in the dark.
uniform float ambient = 0.06;
// Dawn: 0 all night, rising to 1 as the sky pales. Daylight then sweeps in from
// the east edge: pixels with UV.x above sun_front are in the sun.
uniform float dawn = 0.0;
uniform float sun_front = 1.3;

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
	vec3 lit = vec3(0.0);
	vec3 halo = vec3(0.0);
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) {
			break;
		}
		vec4 L = lights[i];
		float d = length(p - L.xy);
		float core = 1.0 - smoothstep(L.z * 0.9, L.z * 1.05, d);
		float spill = exp(-(d * d) / (L.z * L.z * 2.4));
		vec3 c = light_colors[i].rgb * L.w;
		lit += (0.55 * spill + 0.45 * core) * c;
		halo += exp(-d / (L.z * 2.6)) * 0.12 * c;
	}
	// Soft-saturate so overlapping lights never blow out to white.
	lit = 1.0 - exp(-lit);
	halo = (1.0 - exp(-halo * 4.0)) * 0.25;
	vec3 col = night_color + ground * (lit * 1.35 + ambient) + halo;
	if (dawn > 0.0) {
		// The sky pales first, then the sun line crosses the square.
		col += ground * vec3(0.10, 0.08, 0.16) * dawn;
		float day = smoothstep(sun_front - 0.04, sun_front + 0.10, UV.x) * dawn;
		vec3 day_col = ground * vec3(1.85, 1.55, 1.25) + vec3(0.08, 0.06, 0.05) + halo * 0.5;
		col = mix(col, day_col, day);
		float band = exp(-pow((UV.x - sun_front) * 16.0, 2.0)) * dawn;
		col += band * vec3(1.0, 0.72, 0.42) * 0.45;
	}
	// Dither to hide banding in the dark gradients.
	col += (hash(p + fract(TIME)) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0);
}
