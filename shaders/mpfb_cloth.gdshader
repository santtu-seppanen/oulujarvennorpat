shader_type spatial;
// MPFB-paita ja -housut: väri, kiilto ja tuulipuvun sivuraidat (lepoasennon normaalin mukaan, T-asento: kädet +-X).
uniform vec4 color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.96, 0.96, 0.98, 1.0);
uniform float stripes = 0.0;
uniform float triple = 1.0;
uniform float rough = 0.6;
uniform float hem_y = 0.97;  // jalat alle tämän, hihat |x| yli sleeve_x
uniform float sleeve_x = 0.22;
varying vec3 lpos;
varying vec3 lnorm;

float band(float n, float center, float half_w) {
	return 1.0 - smoothstep(half_w, half_w + 0.012, abs(n - center));
}

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}

void fragment() {
	vec3 c = color.rgb;
	if (stripes > 0.5) {
		float s = 0.0;
		float leg_outer = lnorm.x * sign(lpos.x);
		float arm_top = lnorm.y;
		if (lpos.y < hem_y && leg_outer > 0.6) {
			s = triple > 0.5 ? max(band(lnorm.z, 0.0, 0.05), max(band(lnorm.z, 0.2, 0.05), band(lnorm.z, -0.2, 0.05))) : band(lnorm.z, 0.0, 0.16);
		} else if (abs(lpos.x) > sleeve_x && arm_top > 0.6) {
			s = triple > 0.5 ? max(band(lnorm.z, 0.0, 0.05), max(band(lnorm.z, 0.2, 0.05), band(lnorm.z, -0.2, 0.05))) : band(lnorm.z, 0.0, 0.16);
		}
		c = mix(c, stripe_color.rgb, s);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
