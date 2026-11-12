shader_type canvas_item;
// Renders the whole world's ground and water from per-tile data textures:
//  data  R = land biome id (nearest land biome for water tiles)
//        G = landness (1 land / 0 water)   B = water depth   A = river flag
//  flow  RG = river current direction * 0.5 + 0.5
// Land is textured from the terrain atlas with noise-dithered biome borders;
// shorelines follow a noisy contour of the bilinear landness field, so coasts
// are organic curves instead of tile squares. Water is fully procedural:
// depth gradient, drifting ripples, shallow caustics, sun glints, river flow
// streaks and pulsing foam. Everything is snapped to the 32px art grid.

uniform sampler2D data_n : filter_nearest, repeat_disable;
uniform sampler2D data_l : filter_linear, repeat_disable;
uniform sampler2D flow_l : filter_linear, repeat_disable;
uniform sampler2D terrain_atlas : filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec2 world_tiles = vec2(448.0, 448.0);
uniform float tile_count = 15.0;
uniform float daylight = 1.0;

const float TPX = 32.0;
const vec3 SHALLOW_C = vec3(0.30, 0.80, 0.80);
const vec3 DEEP_C = vec3(0.12, 0.42, 0.72);
const vec3 SAND_C = vec3(0.96, 0.84, 0.57);
const vec3 FOAM_C = vec3(0.93, 0.99, 1.0);

float nz(vec2 p) { return texture(noise_tex, p).r; }

void fragment() {
	vec2 tp = UV * world_tiles;
	vec2 px = (floor(tp * TPX) + 0.5) / TPX;          // centre of the art pixel
	vec2 uv = px / world_tiles;
	vec4 dl = texture(data_l, uv);

	float n_a = texture(noise_tex, px * 0.09).r;
	float n_b = texture(noise_tex, px * 0.41 + vec2(0.3, 0.7)).g;
	float edge = dl.g + (n_a - 0.5) * 0.42 + (n_b - 0.5) * 0.16;

	// ---------------------------------------------------------------- land
	vec2 jit = (vec2(texture(noise_tex, px * 0.27).b, texture(noise_tex, px * 0.27 + vec2(0.5)).r) - 0.5) * 0.9;
	vec2 cell = floor(px + jit);
	float lt = floor(texture(data_n, (cell + 0.5) / world_tiles).r * 255.0 + 0.5);
	vec2 base_cell = floor(px);
	float var_i = floor(fract(sin(dot(base_cell, vec2(12.9898, 78.233))) * 43758.5453) * 3.0);
	vec2 in_tile = fract(px);
	vec2 auv = vec2((var_i + in_tile.x) / 3.0, (lt + in_tile.y) / tile_count);
	vec3 land = texture(terrain_atlas, auv).rgb;
	land *= 0.93 + texture(noise_tex, px * 0.021).g * 0.14;   // large soft patches
	bool soft_shore = lt != 9.0 && lt != 7.0 && lt != 8.0;  // not marsh / mountain / snow
	if (soft_shore) {
		float beach = smoothstep(0.5, 0.64, edge);
		vec3 wet = mix(SAND_C * 0.86, SAND_C, smoothstep(0.5, 0.56, edge));
		land = mix(wet, land, beach);
	}

	// --------------------------------------------------------------- water
	float depth = dl.b;
	float river = dl.a;
	vec2 flow = (texture(flow_l, uv).rg - 0.5) * 2.0;
	vec3 water = mix(SHALLOW_C, DEEP_C, smoothstep(0.02, 0.8, depth));
	vec2 drift = vec2(0.035, 0.021) * TIME;
	vec2 fdrift = flow * TIME * 0.9;
	float r1 = texture(noise_tex, px * 0.23 + drift + fdrift).r;
	float r2 = texture(noise_tex, px * 0.29 - drift * 0.8 + fdrift + vec2(0.37, 0.11)).g;
	float rip = r1 + r2;
	water += vec3(0.09, 0.11, 0.10) * smoothstep(1.16, 1.32, rip);
	water -= vec3(0.03, 0.05, 0.04) * smoothstep(0.84, 0.64, rip);
	// caustic shimmer in the shallows
	float c1 = texture(noise_tex, px * 0.6 + vec2(TIME * 0.07, TIME * 0.05)).b;
	float c2 = texture(noise_tex, px * 0.55 - vec2(TIME * 0.06, -TIME * 0.04)).b;
	float caust = clamp(1.0 - abs(c1 - c2) * 7.0, 0.0, 1.0);
	water += vec3(0.10, 0.13, 0.09) * caust * (1.0 - smoothstep(0.0, 0.45, depth)) * 0.7;
	// sun glints
	float g1 = texture(noise_tex, px * 1.3 + vec2(TIME * 0.11, -TIME * 0.07)).r;
	float g2 = texture(noise_tex, px * 1.1 - vec2(TIME * 0.05, TIME * 0.09)).g;
	water += vec3(0.5) * step(0.72, g1 * g2 * 1.25) * daylight;
	// river current streaks
	if (river > 0.05) {
		vec2 fd = length(flow) > 0.05 ? normalize(flow) : vec2(1.0, 0.0);
		vec2 perp = vec2(-fd.y, fd.x);
		float s = texture(noise_tex, vec2(dot(px, perp) * 0.9, dot(px, fd) * 0.12 - TIME * 0.45)).r;
		water += vec3(0.85, 0.95, 1.0) * smoothstep(0.70, 0.78, s) * 0.22 * river;
	}
	// foam that laps the shore
	float foam_band = smoothstep(0.30, 0.5, edge);
	float pulse = 0.5 + 0.5 * sin(TIME * 1.7 + n_a * 12.0);
	float foam = foam_band * step(0.55, pulse * 0.55 + n_b * 0.6 + foam_band * 0.25);
	water = mix(water, FOAM_C, foam * 0.85);

	vec3 col = edge > 0.5 ? land : water;
	col = floor(col * 30.0 + 0.5) / 30.0;   // gentle posterize: pixel-art palette feel
	COLOR = vec4(col, 1.0);
}
