shader_type spatial;
render_mode cull_back;

// RGB = tile colour (sRGB), A = biome id. One texel per tile; see PlanetMesh.
uniform sampler2D tile_colors : source_color, filter_nearest;
uniform float border_strength : hint_range(0.0, 1.0) = 0.35;
uniform int hovered_tile = -1;
uniform int selected_tile = -1;
uniform vec3 hover_color : source_color = vec3(1.0);
uniform vec3 selected_color : source_color = vec3(1.0, 0.82, 0.2);
// Biome ids of water tiles (Biomes.Type) for a bit of sheen.
uniform int water_max_id = 1;

void fragment() {
	ivec2 cell = ivec2(round(UV2));
	vec4 data = texelFetch(tile_colors, cell, 0);
	vec3 col = data.rgb;
	int tile = cell.y * textureSize(tile_colors, 0).x + cell.x;
	int biome = int(round(data.a * 255.0));

	// Tile outlines: thin in screen space, faded out when tiles get tiny.
	float edge = UV.x;
	float w = max(fwidth(edge), 1e-4);
	float line = smoothstep(1.0 - w * 1.5, 1.0 - w * 0.3, edge);
	float fade = 1.0 - smoothstep(0.12, 0.3, w);
	col = mix(col, col * 0.55, line * fade * border_strength);

	if (tile == hovered_tile) {
		col = mix(col, hover_color, 0.25);
		col = mix(col, hover_color, smoothstep(0.8, 0.86, edge) * 0.85);
	}
	if (tile == selected_tile) {
		col = mix(col, selected_color, 0.2);
		col = mix(col, selected_color, smoothstep(0.74, 0.8, edge));
	}

	ALBEDO = col;
	if (biome <= water_max_id) {
		ROUGHNESS = 0.55;
		SPECULAR = 0.3;
	} else {
		ROUGHNESS = 0.95;
		SPECULAR = 0.15;
	}
}
