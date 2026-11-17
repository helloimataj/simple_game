shader_type sky;

uniform vec3 space_color : source_color = vec3(0.01, 0.015, 0.035);
uniform float star_density = 0.0025;

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 cell = floor(dir * 300.0);
	float h = hash(cell);
	float star = step(1.0 - star_density, h);
	float brightness = 0.4 + 0.6 * hash(cell + 7.0);
	COLOR = space_color + vec3(star * brightness);
}
