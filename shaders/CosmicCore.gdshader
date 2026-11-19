// Inlaid Golden-Bezel Cosmic Galaxy Medallion Shader (Astral Constellation Floor Focal Medallions)
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

group_uniforms cosmic_palette;
uniform vec4 deep_color : source_color = vec4(0.025, 0.02, 0.09, 1.0);
uniform vec4 nebula_violet : source_color = vec4(0.34, 0.18, 0.56, 1.0);
uniform vec4 nebula_blue : source_color = vec4(0.16, 0.36, 0.68, 1.0);
uniform vec4 core_gold : source_color = vec4(1.0, 0.88, 0.46, 1.0);
uniform vec4 bezel_gold : source_color = vec4(0.95, 0.80, 0.40, 1.0);

varying vec3 vertex_world;

float cc_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 cc_hash22(vec2 p) {
	vec3 a = fract(p.xyx * vec3(123.34, 234.34, 345.65));
	a += dot(a, a + 34.45);
	return fract(vec2(a.x * a.y, a.y * a.z));
}

float cc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = cc_hash21(i);
	float b = cc_hash21(i + vec2(1.0, 0.0));
	float c = cc_hash21(i + vec2(0.0, 1.0));
	float d = cc_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cc_fbm3(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += amp * cc_noise(p);
		p = rot * p * 2.05 + vec2(7.3, 13.1);
		amp *= 0.5;
	}
	return v;
}

float cc_sharp_star(vec2 uv_p, float scale_f, float thresh, float t_now) {
	vec2 sp_uv = uv_p * scale_f;
	vec2 sp_id = floor(sp_uv);
	vec2 sp_f = fract(sp_uv);
	float sp_rnd = cc_hash21(sp_id + vec2(17.1, 9.3));
	if (sp_rnd < thresh) {
		return 0.0;
	}
	vec2 sp_off = vec2(0.20) + 0.60 * cc_hash22(sp_id);
	float ds = length(sp_f - sp_off);
	float tw = 0.65 + 0.35 * sin(t_now * 4.2 + sp_rnd * 26.0);
	return (1.0 - smoothstep(0.015, 0.055, ds)) * tw;
}

void vertex() {
	vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r_disc = length(p);
	if (r_disc > 1.0) {
		discard;
	}

	vec2 par = clamp((vertex_world.xz - INV_VIEW_MATRIX[3].xz) * 0.016, vec2(-0.18), vec2(0.18));
	float cs = cos(TIME * 0.16);
	float sn = sin(TIME * 0.16);
	vec2 qp = p + par;
	vec2 q = vec2(qp.x * cs - qp.y * sn, qp.x * sn + qp.y * cs);

	float r = length(q);
	float ang = atan(q.y, q.x);

	float n_warp = cc_fbm3(q * 2.4 + vec2(TIME * 0.05, -TIME * 0.04));
	float n_detail = cc_fbm3(q * 5.0 + vec2(n_warp * 1.6));
	float spiral = sin(ang * 2.0 - log(max(r, 0.04)) * 4.0 - TIME * 0.65 + n_warp * 1.3);
	float raw_arm = smoothstep(-0.12, 0.86, spiral) * exp(-r * 1.35);
	float banded_neb = mix(n_detail, floor(n_detail * 5.0) / 5.0, 0.35);
	float dust_lane = smoothstep(0.32, 0.76, 1.0 - abs(n_detail * 2.0 - 1.0));
	float bulge = exp(-r * r * 5.0);

	vec3 neb_mix = mix(nebula_violet.rgb, nebula_blue.rgb, smoothstep(0.28, 0.72, banded_neb));
	vec3 col = deep_color.rgb;
	col = mix(col, neb_mix * 0.95, clamp(raw_arm * 0.75 + banded_neb * 0.36, 0.0, 1.0));
	col *= mix(1.0, 0.42, dust_lane * 0.55 * (1.0 - bulge));
	col = mix(col, core_gold.rgb, clamp(bulge * 0.92, 0.0, 1.0));

	float s1 = cc_sharp_star(q, 11.0, 0.66, TIME);
	float s2 = cc_sharp_star(q + vec2(4.7, 9.2), 21.0, 0.72, TIME * 1.15);
	col = mix(col, vec3(1.0, 0.96, 0.88), clamp(s1 * 0.92 + s2 * 0.75, 0.0, 1.0));

	// Engraved antique-gold astrolabe bezel & sunken inner shadow rim
	float inner_shadow = smoothstep(0.87, 0.935, r_disc) * (1.0 - step(0.945, r_disc));
	col *= mix(1.0, 0.25, inner_shadow);

	float disc_ang = atan(p.y, p.x);
	float notch = smoothstep(0.955, 0.992, abs(cos(disc_ang * 6.0))) * smoothstep(0.90, 0.945, r_disc) * (1.0 - step(0.985, r_disc));
	float outer_bezel = smoothstep(0.945, 0.955, r_disc) * (1.0 - smoothstep(0.985, 0.998, r_disc));
	col = mix(col, bezel_gold.rgb, clamp(outer_bezel + notch * 0.85, 0.0, 1.0));

	ALBEDO = col;
}
