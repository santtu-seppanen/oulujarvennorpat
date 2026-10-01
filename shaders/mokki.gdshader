shader_type spatial;
render_mode cull_disabled;
// Mökkipihan rakenteet (mokki.gd): väri verteksiväristä (sRGB), materiaali verteksivärin alfasta.
// Hirsi, laudoitus kahteen suuntaan, kattopaanu, metalli, lasi, säleikkö, kangas, sammal, mukulakivi,
// ikkunan ja lyhdyn valo (iltaisin, lamp).

uniform float lamp = 0.0;  // 0 päivä .. 1 ilta/yö: lyhdyt ja ikkunat hehkuvat
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 lp;
varying vec3 wp;

const float PLAIN = 1.0;
const float LOG = 0.9;
const float BOARD_U = 0.8;
const float BOARD_V = 0.7;
const float SHINGLE = 0.6;
const float METAL = 0.5;
const float GLASS = 0.4;
const float LATTICE = 0.35;
const float FABRIC = 0.3;
const float GROUND = 0.25;
const float STONE = 0.2;
const float WINDOW = 0.15;
const float LAMP = 0.1;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

bool is(float id, float m) {
	return abs(id - m) < 0.02;
}

void vertex() {
	lp = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Laudat: urat poikittaissuunnassa (across), syy ja sävy laudoittain.
vec3 boards(vec3 c, float across, float along) {
	float w = 0.12;
	float f = fract(across / w);
	float board = floor(across / w);
	c *= mix(0.5, 1.0, smoothstep(0.0, 0.05, f) * smoothstep(1.0, 0.95, f));
	c *= 0.86 + 0.22 * hash21(vec2(board, 3.7));
	c *= 0.9 + 0.2 * texture(noise_tex, vec2(along * 0.06 + board * 0.37, f * 0.5)).r;
	// Laudan päät ja saumat satunnaisesti.
	float seg = fract(along / 2.4 + hash21(vec2(board, 1.1)));
	c *= mix(0.6, 1.0, smoothstep(0.0, 0.004, seg) * smoothstep(1.0, 0.996, seg));
	return c;
}

void fragment() {
	float id = COLOR.a;
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float rough = 0.85;
	float spec = 0.3;
	float metal = 0.0;
	vec3 em = vec3(0.0);
	float n = texture(noise_tex, wp.xz * 0.37 + vec2(wp.y * 0.21)).r;
	if (is(id, LOG)) {
		// Vaakahirret: pyöristetty profiili, tumma sauma, maali kulunut.
		float f = fract(lp.y / 0.19 + 0.35);
		float prof = sin(f * 3.14159);
		c *= 0.55 + 0.45 * pow(prof, 0.35);
		c *= 0.92 + 0.14 * n;
	} else if (is(id, BOARD_U)) {
		c = boards(c, lp.z, lp.x);
	} else if (is(id, BOARD_V)) {
		c = boards(c, lp.x, lp.z);
	} else if (is(id, SHINGLE)) {
		// Kuusikulmiopaanu: rivit korkeuden mukaan, kielekkeet limittäin, rakeinen pinta.
		float rh = 0.095;
		float row = floor(wp.y / rh);
		float fy = fract(wp.y / rh);
		float s = (lp.x + lp.z) / 0.33 + row * 0.5;
		float tab = fract(s);
		float tip = abs(tab - 0.5) * 2.0;
		float edge = smoothstep(0.0, 0.18, fy - tip * 0.35);
		c *= mix(0.45, 1.0, edge);
		c *= 0.8 + 0.4 * hash21(floor(wp.xz * 70.0 + wp.y * 50.0));
		c *= 0.9 + 0.2 * hash21(vec2(floor(s), row));
		rough = 0.95;
	} else if (is(id, METAL)) {
		metal = 0.7;
		rough = 0.38;
		spec = 0.5;
	} else if (is(id, GLASS)) {
		rough = 0.05;
		spec = 0.8;
		em = vec3(1.0, 0.62, 0.3) * lamp * 0.25 * n;
	} else if (is(id, WINDOW)) {
		rough = 0.08;
		spec = 0.8;
		em = vec3(1.0, 0.55, 0.22) * (0.15 + lamp * 1.6) * (0.7 + 0.6 * n);
	} else if (is(id, LAMP)) {
		em = vec3(1.0, 0.7, 0.35) * (0.1 + lamp * 5.0);
	} else if (is(id, LATTICE)) {
		float h = lp.x + lp.z;
		float a = fract((h + lp.y) / 0.14);
		float b = fract((h - lp.y) / 0.14);
		float strip = max(step(a, 0.28), step(b, 0.28));
		c = mix(vec3(0.015), c, strip);
	} else if (is(id, FABRIC)) {
		rough = 0.95;
		spec = 0.15;
		BACKLIGHT = c * 0.6;
	} else if (is(id, GROUND)) {
		// Mustikkaa ja sammalta törmässä: kaksi vihreää kohinasta, välissä ruskeaa.
		float m = texture(noise_tex, wp.xz * 0.21).r;
		float k = texture(noise_tex, wp.xz * 1.3 + vec2(0.3)).r;
		c = mix(vec3(0.05, 0.085, 0.025), vec3(0.11, 0.16, 0.04), m);
		c = mix(c, vec3(0.1, 0.075, 0.04), smoothstep(0.62, 0.8, k));
		c *= 0.8 + 0.4 * hash21(floor(wp.xz * 40.0));
		rough = 0.95;
	} else if (is(id, STONE)) {
		// Mukulakivet: solukuvio, tumma sauma.
		vec2 g = wp.xz * 5.0 + vec2(wp.y * 3.0);
		vec2 i = floor(g);
		float best = 9.0;
		float second = 9.0;
		float tone = 0.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 o = vec2(float(x), float(y));
				vec2 pnt = o + vec2(hash21(i + o), hash21(i + o + 7.7)) - fract(g);
				float d = dot(pnt, pnt);
				if (d < best) {
					second = best;
					best = d;
					tone = hash21(i + o + 3.3);
				} else if (d < second) {
					second = d;
				}
			}
		}
		float gap = smoothstep(0.0, 0.25, sqrt(second) - sqrt(best));
		c *= (0.7 + 0.6 * tone) * mix(0.25, 1.0, gap);
		rough = 0.8;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
	EMISSION = em;
}
