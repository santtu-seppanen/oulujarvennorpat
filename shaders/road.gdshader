shader_type spatial;
// Tiet ja polut maaston päällä. Verteksiväri on tien perusväri ja sen alfa tien laji: 1 asfaltti, 0,7 soratie,
// 0,4 ajoura (ruohoinen keskikaista), 0,15 polku. UV.x: 0 reuna .. 1 keskiviiva .. 0 reuna.
// Soratie: irtosoraa ja pikkukiviä (värivaihtelu ja kohokuvio), renkaiden tiivistämät tummemmat urat,
// vaaleampi irtosoravalli keskellä ja reunoilla, ruoho tunkee reunoista epätasaisesti. Ajouralla ruohokaista
// urien välissä.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Kaukana tie nostetaan kohti katsojaa, ettei karkeampi kaukomaasto peitä sitä (syvyystarkkuus).
	vec3 to_cam = CAMERA_POSITION_WORLD - wpos;
	float d = length(to_cam);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(to_cam / d * clamp(d * 0.003, 0.0, 4.0), 0.0)).xyz;
}

float nz(vec2 p) {
	return texture(noise_tex, p).r;
}

void fragment() {
	float kind = COLOR.a;
	float lat = 1.0 - UV.x;  // 0 keskellä, 1 reunalla
	float n = nz(wpos.xz * 0.35);
	float f = nz(wpos.xz * 3.1);
	vec3 col = COLOR.rgb * (0.8 + n * 0.25 + (f - 0.5) * 0.2);
	float rough = 0.9;
	float edge = 0.35;
	if (kind > 0.25 && kind < 0.85) {
		// Sorakivet: kaksi mittakaavaa pilkkuja, osa vaaleampia ja punertavia, osa tummia.
		float s1 = nz(wpos.xz * 9.0);
		float s2 = nz(wpos.xz * 23.0 + 7.3);
		float pebble = smoothstep(0.62, 0.7, s1) + smoothstep(0.66, 0.72, s2) * 0.8;
		float dark = smoothstep(0.38, 0.3, s2);
		// Värit lineaarisina (ALBEDO): harmaanruskea murske n. 0,15-0,3.
		vec3 gravel = mix(vec3(0.16, 0.145, 0.12), vec3(0.2, 0.18, 0.145), n);
		gravel = mix(gravel, vec3(0.3, 0.27, 0.22), pebble * 0.6);
		gravel = mix(gravel, vec3(0.25, 0.16, 0.11), smoothstep(0.7, 0.8, s1) * 0.45);  // punertava graniittimurske
		gravel = mix(gravel, vec3(0.06, 0.055, 0.05), dark * 0.6);
		// Renkaiden urat: tiivistynyt, tummempi ja sileämpi; urien välissä ja reunoilla irtosoraa.
		float wob = (nz(wpos.xz * 0.08) - 0.5) * 0.18;
		float rut = 1.0 - smoothstep(0.08, 0.2, abs(lat - 0.52 - wob));
		gravel = mix(gravel, vec3(0.1, 0.092, 0.08) + (n - 0.5) * 0.02, rut * 0.75);
		rough = mix(0.95, 0.78, rut);
		// Ajouralla ruoho urien välissä keskellä.
		if (kind < 0.55) {
			float grass = (1.0 - smoothstep(0.18, 0.34, lat + (f - 0.5) * 0.15)) * smoothstep(0.25, 0.55, n + 0.2);
			gravel = mix(gravel, mix(vec3(0.06, 0.1, 0.025), vec3(0.12, 0.15, 0.04), f), grass);
		}
		// Reunat: ruohotuppaita ja sammalta sorassa.
		float tuft = smoothstep(0.72, 0.95, lat) * smoothstep(0.45, 0.7, nz(wpos.xz * 1.7));
		gravel = mix(gravel, mix(vec3(0.07, 0.1, 0.03), vec3(0.14, 0.15, 0.06), f), tuft * 0.8);
		col = gravel;
		// Kohokuvio pikkukivistä: normaalia kallistetaan sorakohinan mukaan.
		float e = 0.012;
		float hx = nz((wpos.xz + vec2(e, 0.0)) * 9.0) - s1;
		float hz = nz((wpos.xz + vec2(0.0, e)) * 9.0) - s1;
		vec3 bump = normalize(vec3(-hx * 3.0 * (1.0 - rut * 0.7), 1.0, -hz * 3.0 * (1.0 - rut * 0.7)));
		NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(bump, 0.0)).xyz, 0.6));
		edge = 0.28;
	} else if (kind <= 0.25) {
		// Polku: kulunut multa, juuria ja neulasia.
		col = mix(col, vec3(0.3, 0.24, 0.16), smoothstep(0.6, 0.75, nz(wpos.xz * 6.0)) * 0.5);
	}
	ALBEDO = col;
	// Reunat sulautuvat maastoon epätasaisesti.
	ALPHA = smoothstep(0.0, edge, UV.x + (n - 0.5) * 0.3 + (f - 0.5) * 0.08);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = rough;
	SPECULAR = 0.25;  // sora ja multa eivät heijasta taivasta
}
