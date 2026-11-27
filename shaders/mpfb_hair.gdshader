shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// MPFB-hiukset ja kulmat: alfa tekstuurista, väri look-arvosta ja tekstuurin kirkkaus suortuvien vaihteluna.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(0.25, 0.18, 0.12, 1.0);

void fragment() {
	vec4 t = texture(tex, UV);
	float l = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	ALBEDO = color.rgb * clamp(0.45 + l * 2.4, 0.2, 1.5);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.55;
	SPECULAR = 0.4;
}
