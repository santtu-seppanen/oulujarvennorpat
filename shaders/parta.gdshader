shader_type spatial;
// Sänkiparta: leukaa ja poskia peittävä kuori pään päällä; yläreuna (poskipää), suun aukko ja karhea reuna discardilla.
uniform vec4 color : source_color = vec4(0.15, 0.1, 0.07, 1.0);
uniform float top_y = 0.035;      // parran yläraja (paikallinen y)
uniform float mouth_y = 0.0;  // suun keskikorkeus
uniform float mouth_w = 0.03;
uniform float density = 0.85;
uniform vec3 sc = vec3(1.0);
varying vec3 lp;

float h(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	lp = VERTEX * sc;
}

void fragment() {
	float edge = smoothstep(top_y - 0.03, top_y, lp.y);  // harvenee ylöspäin
	if (lp.y > top_y) discard;
	// suun alue (edessä, z negatiivinen) vapaaksi, viikset sen yläpuolella jäävät
	bool front = lp.z < -0.02;
	if (front && abs(lp.x) < mouth_w && lp.y > mouth_y - 0.012 && lp.y < mouth_y + 0.012) discard;
	float n = h(floor(lp * 800.0));
	if (n > density * (1.0 - 0.8 * edge)) discard;
	ALBEDO = color.rgb * (0.7 + 0.5 * n);
	ROUGHNESS = 1.0;
}
