shader_type spatial;
// Tiet ja polut maaston päällä: verteksiväri (sora, asfaltti, polku), kohinavaihtelu ja reunat pehmeinä.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Kaukana tie nostetaan kohti katsojaa, ettei karkeampi kaukomaasto peitä sitä (syvyystarkkuus).
	vec3 to_cam = CAMERA_POSITION_WORLD - wpos;
	float d = length(to_cam);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(to_cam / d * clamp(d * 0.003, 0.0, 4.0), 0.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, wpos.xz * 0.35).r;
	float f = texture(noise_tex, wpos.xz * 3.1).r;
	ALBEDO = COLOR.rgb * (0.8 + n * 0.25 + (f - 0.5) * 0.2);
	// UV.x: 0 reuna .. 1 keskiviiva .. 0 reuna; reunat sulautuvat maastoon.
	ALPHA = smoothstep(0.0, 0.35, UV.x + (n - 0.5) * 0.3);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
}
