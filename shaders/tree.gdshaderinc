// Puun sijoitus datatekstuurista (trees.gd, assets/map/puut.bin): MultiMeshin instanssi INSTANCE_ID + base
// = puun indeksi. tree_a: x, y, z, pituus; tree_b: latvuksen säde (x 40), laji, kaksi satunnaislukua.
// Malli on tehty viitepituudelle ref_h ja latvuksen säteelle ref_r; puu skaalataan omiin mittoihinsa.

uniform sampler2D tree_a : filter_nearest, repeat_disable;
uniform sampler2D tree_b : filter_nearest, repeat_disable;
uniform float ref_h = 10.0;
uniform float ref_r = 2.0;
// Tarkkuustaso puukohtaisesti: puu piirretään tällä mallilla, kun sen etäisyys katsojasta (lod_eye, sama
// kaikissa piirtokierroksissa myös varjoissa) on välillä [lod_min, lod_max). Muuten kolmiot kutistuvat pisteeksi.
global uniform vec3 lod_eye;
uniform float lod_min = 0.0;
uniform float lod_max = 100000.0;
// Rungot levenevät pituuden mukaan (ei latvuksen leveyden), etteivät leveälatvaiset saa paksuja runkoja.
uniform bool trunk = false;
instance uniform int base = 0;

varying vec3 wpos;
varying float tint;

void place_tree(inout vec3 v, inout vec3 n, int iid, out float tn) {
	int w = textureSize(tree_a, 0).x;
	int i = base + iid;
	ivec2 c = ivec2(i % w, i / w);
	vec4 a = texelFetch(tree_a, c, 0);
	vec4 b = texelFetch(tree_b, c, 0);
	float r = b.x * 255.0 / 40.0;
	float sy = a.w / ref_h;
	float sx = trunk ? sy * 0.85 : clamp(r / ref_r, sy * 0.55, sy * 1.6);
	float d = distance(a.xz, lod_eye.xz);
	if (d < lod_min || d >= lod_max) {
		v = vec3(0.0);
		tn = 0.0;
		return;
	}
	float ang = b.z * 6.2831853;
	float ca = cos(ang);
	float sa = sin(ang);
	vec2 xz = vec2(ca * v.x - sa * v.z, sa * v.x + ca * v.z) * sx;
	v = vec3(xz.x, v.y * sy, xz.y) + a.xyz;
	vec2 nxz = vec2(ca * n.x - sa * n.z, sa * n.x + ca * n.z) / sx;
	n = normalize(vec3(nxz.x, n.y / sy, nxz.y));
	tn = b.w - 0.5;
}
