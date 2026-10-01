shader_type spatial;
// Maasto: tasaruudukon pisteet nostetaan korkeusmallin korkeuteen (terrain.gd: lähiruudukko 2 m, kauko 16 m).
// Korkeus luetaan texelFetchillä ja kolmioidaan kuten HeightMapShape3D, joten näkyvä pinta = törmäyspinta.
// Pinnat maastotietokannan luokista (FOREST, WATER, ...), rosoiset reunat kohinalla, rinteissä kalliota,
// järven pohja tummuu syvemmälle.

uniform sampler2D near_h : filter_nearest, repeat_disable;
uniform sampler2D far_h : filter_nearest, repeat_disable;
uniform sampler2D near_c : filter_nearest, repeat_disable;
uniform sampler2D far_c : filter_nearest, repeat_disable;
uniform float near_half = 1000.0;
uniform float near_step = 2.0;
uniform float far_half = 5120.0;
uniform float far_step = 16.0;
uniform float open_depth = -9.0;
// Kaukoverkko painetaan lähiverkon alle sen alueella (sauma piiloon).
uniform float sink = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform vec3 col_a[12] : source_color;
uniform vec3 col_b[12] : source_color;
uniform float scale[12];

varying vec3 wpos;
varying float depth;

float grid_h(sampler2D tex, float half, float step, vec2 p) {
	int n = textureSize(tex, 0).x;
	vec2 f = clamp((p + half) / step, vec2(0.0), vec2(float(n - 1)));
	ivec2 i = min(ivec2(f), ivec2(n - 2));
	vec2 uv = f - vec2(i);
	float h00 = texelFetch(tex, i, 0).r;
	float h10 = texelFetch(tex, i + ivec2(1, 0), 0).r;
	float h01 = texelFetch(tex, i + ivec2(0, 1), 0).r;
	float h11 = texelFetch(tex, i + ivec2(1, 1), 0).r;
	if (uv.x + uv.y <= 1.0) {
		return h00 + (h10 - h00) * uv.x + (h01 - h00) * uv.y;
	}
	return h11 + (h01 - h11) * (1.0 - uv.x) + (h10 - h11) * (1.0 - uv.y);
}

float height(vec2 p) {
	if (abs(p.x) <= near_half && abs(p.y) <= near_half) {
		return grid_h(near_h, near_half, near_step, p);
	}
	if (abs(p.x) <= far_half && abs(p.y) <= far_half) {
		return grid_h(far_h, far_half, far_step, p);
	}
	return open_depth;
}

int surface(vec2 p) {
	if (abs(p.x) < near_half && abs(p.y) < near_half) {
		int n = textureSize(near_c, 0).x;
		ivec2 i = clamp(ivec2((p + near_half) / near_step), ivec2(0), ivec2(n - 1));
		return int(texelFetch(near_c, i, 0).r * 255.0 + 0.5);
	}
	if (abs(p.x) < far_half && abs(p.y) < far_half) {
		int n = textureSize(far_c, 0).x;
		ivec2 i = clamp(ivec2((p + far_half) / far_step), ivec2(0), ivec2(n - 1));
		return int(texelFetch(far_c, i, 0).r * 255.0 + 0.5);
	}
	return 1;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float y = height(wp.xz);
	if (sink > 0.0 && abs(wp.x) < near_half + far_step && abs(wp.z) < near_half + far_step) {
		y -= sink;
	}
	VERTEX.y = y - MODEL_MATRIX[3].y;
	// Normaali korkeuseroista (ruudun kokoinen askel).
	float e = (abs(wp.x) <= near_half && abs(wp.z) <= near_half) ? near_step : far_step;
	float dx = height(wp.xz + vec2(e, 0.0)) - height(wp.xz - vec2(e, 0.0));
	float dz = height(wp.xz + vec2(0.0, e)) - height(wp.xz - vec2(0.0, e));
	NORMAL = normalize(vec3(-dx, 2.0 * e, -dz));
	wpos = vec3(wp.x, y, wp.z);
	depth = -y;
}

vec3 surf_col(int k, vec2 p, out float fine) {
	float s = scale[k];
	float n = texture(noise_tex, p * s * 0.15).r;
	float m = texture(noise_tex, p * s).r;
	fine = texture(noise_tex, p * s * 6.0).r;
	float t = clamp(n * 0.6 + m * 0.4 + (fine - 0.5) * 0.3, 0.0, 1.0);
	return mix(col_a[k], col_b[k], smoothstep(0.2, 0.8, t));
}

void fragment() {
	vec2 p = wpos.xz;
	// Rosoinen reuna: luokka luetaan kohinalla siirretystä kohdasta.
	vec2 jit = (vec2(texture(noise_tex, p * 0.09).r, texture(noise_tex, p * 0.09 + 0.37).r) - 0.5) * 3.0;
	int k = surface(p + jit);
	float fine;
	vec3 col = surf_col(k, p, fine);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - wn.y;
	if (k != 1 && k != 11) {
		// Jyrkät rinteet: hiekkaa ja kiveä.
		float f2;
		vec3 rock = surf_col(3, p, f2);
		col = mix(col, rock, smoothstep(0.35, 0.6, slope));
	}
	// Märkä rantaviiva ja pohja: tummempi ja vihertävä syvemmällä.
	float wet = smoothstep(0.3, -0.05, wpos.y);
	col = mix(col, col * vec3(0.7, 0.72, 0.7), wet);
	float d = clamp(depth / 6.0, 0.0, 1.0);
	col = mix(col, vec3(0.12, 0.18, 0.16), d * 0.85);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.4, wet);
	SPECULAR = 0.25;
	NORMAL_MAP = normalize(vec3(0.5 + (fine - 0.5) * 0.35, 0.5 + (texture(noise_tex, p * 2.3).r - 0.5) * 0.35, 1.0));
}
