shader_type canvas_item;
// Humalan näkymä: kahdentuva ja huojuva kuva, reunojen tummuus; sammuessa lähes musta.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;  // 0 selvä .. 1 tolkuton
uniform float out_k = 0.0;  // 0 hereillä .. 1 sammunut

void fragment() {
	float t = TIME;
	vec2 sway = vec2(sin(t * 0.6), cos(t * 0.45)) * 0.006 * amount;
	vec2 off = vec2(sin(t * 0.9), cos(t * 0.7)) * 0.018 * amount;
	vec2 uv = SCREEN_UV + sway;
	vec3 a = textureLod(screen, uv, amount * 0.8).rgb;
	vec3 b = textureLod(screen, uv + off, amount * 0.8).rgb;
	vec3 c = mix(a, b, 0.45 * min(amount * 1.4, 1.0));
	float vig = smoothstep(0.95, 0.25, length(SCREEN_UV - 0.5));
	c *= mix(1.0, vig, 0.55 * amount);
	c = mix(c, vec3(0.0), out_k * 0.92);
	COLOR = vec4(c, 1.0);
}
