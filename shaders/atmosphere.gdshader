shader_type spatial;
// Drawn on the back faces of a sphere a little larger than the planet, so it
// only shows as a halo around the globe and still works with the camera inside.
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled;

uniform vec3 glow_color : source_color = vec3(0.3, 0.55, 1.0);
uniform float planet_radius = 10.0;
uniform float thickness = 0.5;
uniform float intensity = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 dir = normalize(world_pos - cam);
	// Closest approach of the view ray to the planet centre.
	float d = length(cam - dir * dot(cam, dir));
	float glow = exp(-max(d - planet_radius, 0.0) / thickness);
	ALBEDO = glow_color * glow * intensity;
}
