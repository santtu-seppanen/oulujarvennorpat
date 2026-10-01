shader_type sky;
// Taivas: liukuväri, aurinko, iltarusko, tähdet ja staattiset kumpupilvet (fbm-kohina).
// Sävyt ja auringon suunta tulevat sun.gd:stä pelin kellonajan mukaan.

uniform vec3 top_color : source_color = vec3(0.22, 0.42, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.85, 0.9);
uniform vec3 ground_color : source_color = vec3(0.42, 0.48, 0.42);
uniform float cloud_coverage = 0.5;
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.86);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 glow_color : source_color = vec3(0.0);  // iltarusko horisontissa auringon puolella
uniform float night = 0.0;        // 0 päivä .. 1 yö (tähdet)
uniform float cloud_light = 1.0;  // pilvien valaistus (hämärässä tummat)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
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

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	// Iltarusko: oranssi vyö horisontissa auringon suunnassa, kapenee ylöspäin ja sivuille.
	vec2 dh = normalize(d.xz + vec2(1e-5));
	vec2 sh = normalize(sun_dir.xz + vec2(1e-5));
	float side = max(dot(dh, sh), 0.0);
	float band = exp(-max(h, 0.0) * 9.0);
	col += glow_color * band * (0.25 + 0.75 * pow(side, 3.0));
	col += glow_color * vec3(0.6, 0.35, 0.6) * exp(-max(h, 0.0) * 3.0) * pow(side, 1.5) * 0.25;
	if (h < 0.0) {
		col = mix(col, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}
	float sd = max(dot(d, sun_dir), 0.0);
	// Hehku auringon ympärillä ja itse kiekko (näkyy vain horisontin yläpuolella).
	float above = smoothstep(-0.004, 0.002, h);
	col += sun_color * pow(sd, 12.0) * 0.25 * smoothstep(-0.1, 0.02, sun_dir.y);
	col += sun_color * smoothstep(0.99996, 0.99999, sd) * 18.0 * above;
	col += sun_color * pow(sd, 1500.0) * 4.0 * above;
	// Tähdet yöllä.
	if (night > 0.0 && h > 0.0) {
		vec2 g = d.xz / (h + 0.25) * 220.0;
		float s = step(0.997, hash(floor(g)));
		col += vec3(s * night * smoothstep(0.02, 0.2, h) * (0.6 + 0.4 * hash(floor(g) + 3.1)));
	}
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 1.3;
		float c = fbm(uv * 1.4);
		c = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.22, c);
		float shade = fbm(uv * 1.4 + vec2(0.35, 0.2));
		vec3 ccol = mix(vec3(1.0, 0.98, 0.95), vec3(0.66, 0.7, 0.78), shade * 0.7) * cloud_light;
		ccol = mix(ccol, horizon_color * 0.8, 0.3 * (1.0 - cloud_light));
		ccol += sun_color * pow(sd, 6.0) * 0.3 * smoothstep(-0.05, 0.05, sun_dir.y);
		// Matalan auringon alta valaisemat pilvien reunat: punaoranssi hehku auringon puolella.
		ccol += glow_color * (1.0 - shade) * (0.35 + 0.9 * pow(side, 2.0)) * exp(-h * 2.5);
		col = mix(col, ccol, c * smoothstep(0.0, 0.18, h));
	}
	COLOR = col;
}
