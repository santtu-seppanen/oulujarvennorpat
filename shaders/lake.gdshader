shader_type spatial;
render_mode cull_disabled, depth_draw_always;
// Oulujärven ja lampien pinta: liikkuvat aaltonormaalit, Fresnel-heijastus, läpinäkyvä matalikko (pohja näkyy
// rannassa), syvemmällä tumma. clip_land: maaston pintakartta leikkaa veden pois matalilta maa-alueilta, jotka
// ovat järven pinnan alapuolella mutta eivät järveä (rantavallien takaiset notkot).

uniform vec3 deep : source_color = vec3(0.04, 0.12, 0.16);
uniform vec3 shallow : source_color = vec3(0.22, 0.36, 0.36);
uniform float clarity = 0.55;
uniform bool clip_land = false;
uniform sampler2D near_c : filter_nearest, repeat_disable;
uniform sampler2D far_c : filter_nearest, repeat_disable;
uniform float near_half = 1000.0;
uniform float near_step = 2.0;
uniform float far_half = 5120.0;
uniform float far_step = 16.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float waves(vec2 p) {
	return texture(noise_tex, p * 0.05 + vec2(TIME * 0.010, TIME * 0.006)).r
		+ texture(noise_tex, p * 0.13 - vec2(TIME * 0.008, -TIME * 0.012)).r * 0.6
		+ texture(noise_tex, p * 0.41 + vec2(TIME * 0.03, TIME * 0.02)).r * 0.25;
}

bool land_at(vec2 p) {
	int k = 1;
	if (abs(p.x) < near_half && abs(p.y) < near_half) {
		int n = textureSize(near_c, 0).x;
		k = int(texelFetch(near_c, clamp(ivec2((p + near_half) / near_step), ivec2(0), ivec2(n - 1)), 0).r * 255.0 + 0.5);
	} else if (abs(p.x) < far_half && abs(p.y) < far_half) {
		int n = textureSize(far_c, 0).x;
		k = int(texelFetch(far_c, clamp(ivec2((p + far_half) / far_step), ivec2(0), ivec2(n - 1)), 0).r * 255.0 + 0.5);
	}
	return k != 1 && k != 11;
}

void fragment() {
	vec2 p = wpos.xz;
	if (clip_land && land_at(p)) {
		discard;
	}
	float e = 0.2;
	float a = waves(p);
	float bx = waves(p + vec2(e, 0.0)) - a;
	float bz = waves(p + vec2(0.0, e)) - a;
	vec3 nw = normalize(vec3(-bx * 3.0, 1.0, -bz * 3.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// Veden paksuus katselusuunnassa syvyyspuskurista.
	float zb = texture(depth_tex, SCREEN_UV).r;
	vec4 vb = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zb, 1.0);
	vb.xyz /= vb.w;
	float thick = max(VERTEX.z - vb.z, 0.0);
	float t = 1.0 - exp(-thick * clarity);
	vec2 refr = SCREEN_UV + nw.xz * 0.012 * clamp(thick, 0.0, 1.0);
	vec3 below = texture(screen_tex, refr).rgb;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 water = mix(shallow, deep, t);
	ALBEDO = vec3(0.0);
	EMISSION = mix(below * mix(vec3(0.85, 0.95, 0.9), water * 2.0, t), water * 0.4, t * 0.8) * (1.0 - fres);
	ALPHA = 1.0;
	ROUGHNESS = 0.05;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
