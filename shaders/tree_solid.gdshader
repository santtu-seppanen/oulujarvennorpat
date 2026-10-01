shader_type spatial;
render_mode world_vertex_coords;
// Puun runko ja umpinainen latvus (keski- ja kaukotaso). bark = koivun tuohi, muuten tasaväri.

#include "res://shaders/tree.gdshaderinc"

uniform vec3 color : source_color = vec3(0.3, 0.45, 0.2);
uniform bool bark = false;
uniform bool foliage = true;
uniform float sway = 0.04;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying float ly;

void vertex() {
	ly = VERTEX.y;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float tn;
	place_tree(v, n, INSTANCE_ID, tn);
	tint = tn;
	wpos = v;
	if (foliage) {
		float s = sin(TIME * 1.2 + v.x * 0.13 + v.z * 0.09) * sway * max(ly - 2.0, 0.0) * 0.1;
		v.x += s;
		v.z += s * 0.5;
	}
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
	float n = texture(noise_tex, wpos.xz * 0.2 + vec2(wpos.y * 0.15)).r;
	vec3 c = color;
	if (bark) {
		float m = texture(noise_tex, vec2(wpos.x * 0.6 + wpos.z * 0.4, wpos.y * 1.5)).r;
		c = mix(vec3(0.92, 0.91, 0.87), vec3(0.08), smoothstep(0.6, 0.66, m));
	} else if (foliage) {
		c *= (0.7 + n * 0.6) * (1.0 + tint * 0.35);
	} else {
		c *= 0.8 + n * 0.4;
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	if (foliage) {
		BACKLIGHT = c * 0.3;
	}
}
