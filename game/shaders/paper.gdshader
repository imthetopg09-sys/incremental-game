shader_type canvas_item;

// Warm watercolor paper for the Day Town: a morning sky wash, a low sun in the
// east, soft blotches where the pigment pooled, and fine grain.
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform vec2 sun_pos = vec2(1010.0, 360.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * rect_size;
	vec3 col = mix(vec3(0.97, 0.83, 0.70), vec3(0.97, 0.93, 0.86), smoothstep(0.0, 0.75, UV.y));
	float d = length(p - sun_pos);
	col = mix(col, vec3(1.0, 0.96, 0.84), exp(-d * d / (2.0 * 120.0 * 120.0)) * 0.9);
	col += vec3(1.0, 0.72, 0.42) * exp(-d / 240.0) * 0.10;
	// Pigment pooled unevenly across the wash.
	col *= 0.93 + 0.09 * fbm(p / 170.0 + vec2(3.1, 7.7));
	// Paper fibre and grain.
	col -= 0.035 * fbm(p / 5.0);
	col *= 0.985 + 0.015 * hash(floor(p));
	COLOR = vec4(col, 1.0);
}
