shader_type canvas_item;
// Creature colour variants.
//   1 = shiny  (hue-shifted, extra saturation)
//   2 = silver (metallic grey ramp + moving sheen)
//   3 = gold   (metallic gold ramp + moving sheen)

uniform int mode = 0;
uniform float sheen_offset = 0.0;
varying vec2 local_pos;

vec3 hue_shift(vec3 color, float hue) {
	const vec3 k = vec3(0.57735);
	float c = cos(hue);
	return color * c + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - c);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	if (mode == 1) {
		vec3 h = hue_shift(c.rgb, 2.4);
		float g = dot(h, vec3(0.333));
		c.rgb = clamp(mix(vec3(g), h, 1.35) * 1.06, 0.0, 1.0);
	} else if (mode == 2) {
		c.rgb = mix(vec3(0.33, 0.36, 0.44), vec3(0.97, 0.99, 1.0), clamp(l * 1.35, 0.0, 1.0));
	} else if (mode == 3) {
		c.rgb = mix(vec3(0.45, 0.27, 0.05), vec3(1.0, 0.9, 0.42), clamp(l * 1.4, 0.0, 1.0));
	}
	if (mode >= 2) {
		float band = (local_pos.x + local_pos.y * 0.6) * 0.04 - mod(TIME * 0.9 + sheen_offset, 4.0) + 1.5;
		c.rgb += vec3(0.45) * smoothstep(0.18, 0.0, abs(band));
	}
	COLOR = c;
}
