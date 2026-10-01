shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_prepass_alpha;
// Lähipuun latvus läpikuultavista korteista (foliage.gd): lehti-/neulastekstuuri alfaleikkauksella, tuulihuojunta.

#include "res://shaders/tree.gdshaderinc"

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(0.3, 0.45, 0.2);
uniform float sway = 0.06;
uniform float cutoff = 0.45;

void vertex() {
	float hh = max(VERTEX.y, 0.0);
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float tn;
	place_tree(v, n, INSTANCE_ID, tn);
	tint = tn;
	wpos = v;
	float s = sin(TIME * 1.3 + v.x * 0.13 + v.z * 0.09) * sway * hh * 0.12
		+ sin(TIME * 3.7 + v.x * 1.3 + v.y) * sway * 0.15;
	v.x += s;
	v.z += s * 0.6;
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	// Kameran edessä (alle 3 m) lehvästö häivytetään rasterilla, ettei se peitä näkymää.
	float cam_d = length(VERTEX);
	if (cam_d < 3.0) {
		float dither = fract(dot(FRAGCOORD.xy, vec2(0.7548777, 0.5698403)));
		if (dither > (cam_d - 0.8) / 2.2) {
			discard;
		}
	}
	vec4 t = texture(leaf_tex, UV);
	float n = texture(noise_tex, wpos.xz * 0.15 + vec2(wpos.y * 0.1)).r;
	vec3 c = color * (1.0 + tint * 0.35);
	ALBEDO = t.rgb * c * (0.75 + n * 0.5);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = cutoff;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = t.rgb * c * 0.55;
}
