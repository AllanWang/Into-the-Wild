shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 hazard_color : source_color = vec4(1.0, 0.20, 0.28, 1.0);
uniform vec4 border_danger_color : source_color = vec4(1.0, 0.12, 0.20, 1.0);
uniform float inner_ratio : hint_range(0.0, 0.95) = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform int hazard_stage = 0; // 0=Telegraph, 1=Quake Eruption, 2=Active Acid Pool, 3=Clock-Dial Wedge, 4=Whiteout Storm, 5=Chronos Safe Circle, 6=Vine Slam Ribbon Telegraph, 7=Vine Slam Ribbon Impact
uniform float fade_out : hint_range(0.0, 1.0) = 1.0;
uniform float safe_angle = 0.0;
uniform float safe_half_width = 0.567;
uniform vec2 safe_center_uv = vec2(0.0, 0.0);
uniform float safe_radius_uv = 0.16;

float hz_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hz_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hz_hash21(i);
	float b = hz_hash21(i + vec2(1.0, 0.0));
	float c = hz_hash21(i + vec2(0.0, 1.0));
	float d = hz_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float hz_fbm3(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += amp * hz_noise(p);
		p = rot * p * 2.04 + vec2(9.7, 5.1);
		amp *= 0.5;
	}
	return v;
}

float hz_pinpoint_star(vec2 uv_p, float scale_f, float thresh, float t_now) {
	vec2 g = uv_p * scale_f;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float rnd = hz_hash21(id);
	if (rnd < thresh) {
		return 0.0;
	}
	vec2 center = vec2(0.22) + 0.56 * vec2(hz_hash21(id + vec2(3.1, 7.4)), hz_hash21(id + vec2(9.2, 2.7)));
	float d = length(f - center);
	float tw = 0.55 + 0.45 * sin(t_now * 5.0 + rnd * 28.0);
	return (1.0 - smoothstep(0.012, 0.048, d)) * tw;
}

void fragment() {
	vec3 col = hazard_color.rgb;
	float alpha = 0.0;

	if (hazard_stage == 6 || hazard_stage == 7) {
		float ax = abs(UV.x - 0.5) * 2.0;
		float along = 1.0 - UV.y;
		float side_border = smoothstep(0.84, 0.92, ax) * (1.0 - smoothstep(0.985, 1.0, ax));
		float base_cap = (1.0 - smoothstep(0.012, 0.036, along));
		float tip_cap = smoothstep(0.962, 0.985, along);
		float rim = clamp(side_border + base_cap + tip_cap, 0.0, 1.0);
		float center_spine = (1.0 - smoothstep(0.03, 0.14, ax)) * step(0.015, along) * step(along, 0.985);

		if (hazard_stage == 6) {
			float fill_body = 1.0 - smoothstep(progress - 0.03, progress + 0.018, along);
			float sweep_front = smoothstep(progress - 0.09, progress, along) * (1.0 - smoothstep(progress, progress + 0.025, along));
			float chev = smoothstep(0.58, 0.92, sin((along * 18.0 - ax * 2.0 - TIME * 7.5) * 3.14159));
			float urgent = step(0.76, progress) * (0.5 + 0.5 * sin(TIME * 42.0));

			vec3 base_tint = mix(hazard_color.rgb, border_danger_color.rgb, 0.36 * fill_body + 0.48 * urgent);
			base_tint = mix(base_tint, vec3(0.94, 1.0, 0.56), sweep_front * 0.72 + center_spine * 0.28 + rim * (0.45 + 0.45 * urgent));
			col = base_tint;
			alpha = (0.18 + fill_body * (0.24 + 0.10 * chev) + sweep_front * 0.62 + center_spine * 0.24 + rim * 0.95) * fade_out;
		} else {
			float lash_stripes = smoothstep(0.50, 0.95, abs(sin(along * 24.0 - ax * 6.0)));
			col = mix(border_danger_color.rgb, vec3(0.92, 1.0, 0.64), center_spine * 0.75 + lash_stripes * 0.35);
			alpha = (0.56 + center_spine * 0.32 + lash_stripes * 0.24 + rim * 0.95) * fade_out;
		}
	} else {
		vec2 p = (UV - vec2(0.5)) * 2.0;
		float r = length(p);
		if (r > 1.02 || r < inner_ratio * 0.96) {
			discard;
		}

		float ang = atan(p.y, p.x);
		float dash_wave = sin(ang * 16.0 - TIME * 7.5);
		float outer_band = smoothstep(0.90, 0.94, r) * (1.0 - smoothstep(0.99, 1.02, r));
		float inner_band = (inner_ratio > 0.05)
			? smoothstep(inner_ratio - 0.02, inner_ratio, r) * (1.0 - smoothstep(inner_ratio + 0.04, inner_ratio + 0.07, r))
			: 0.0;
		float dashed_rim = (outer_band + inner_band) * mix(0.35, 1.0, step(0.0, dash_wave));

		if (hazard_stage == 0) {
			float span = max(0.05, 1.0 - inner_ratio);
			float fill_r = inner_ratio + span * progress;
			float sweep_front = smoothstep(fill_r - 0.07, fill_r, r) * (1.0 - smoothstep(fill_r, fill_r + 0.025, r));
			float inside_fill = step(inner_ratio, r) * (1.0 - smoothstep(fill_r - 0.02, fill_r + 0.02, r));
			float ripple = 0.5 + 0.5 * sin((r - TIME * 1.9) * 22.0);
			float urgent = step(0.76, progress) * (0.5 + 0.5 * sin(TIME * 42.0));

			col = mix(hazard_color.rgb, border_danger_color.rgb, 0.45 + 0.45 * urgent);
			col = mix(col, vec3(1.0, 0.92, 0.85), sweep_front * 0.65 + urgent * 0.35);
			alpha = inside_fill * (0.20 + 0.12 * ripple) + sweep_front * 0.75 + dashed_rim * 0.96;
		} else if (hazard_stage == 1) {
			float rays = abs(sin(ang * 10.0 + r * 6.0));
			float crack = smoothstep(0.65, 0.95, rays);
			col = mix(border_danger_color.rgb, vec3(1.0, 0.78, 0.62), crack * 0.55);
			alpha = (0.50 + crack * 0.32 + dashed_rim * 0.96) * fade_out;
		} else if (hazard_stage == 3) {
			float da = abs(atan(sin(ang - safe_angle), cos(ang - safe_angle)));
			bool in_safe = (da <= safe_half_width);
			float edge_dist = abs(da - safe_half_width);
			float wedge_edge = (1.0 - smoothstep(0.010, 0.036, edge_dist)) * step(0.06, r);
			float hand_ang = safe_angle + 3.14159265 + progress * 6.2831853;
			float hand_d = abs(atan(sin(ang - hand_ang), cos(ang - hand_ang)));
			float hand_line = (1.0 - smoothstep(0.008, 0.028, hand_d)) * step(0.05, r);
			float trail_diff = mod(hand_ang - ang + 6.2831853, 6.2831853);
			float hand_trail = (1.0 - smoothstep(0.0, 0.52, trail_diff)) * step(0.07, r) * step(r, 0.95);
			float astrolabe_rings = (1.0 - smoothstep(0.005, 0.015, abs(r - 0.36))) + (1.0 - smoothstep(0.005, 0.015, abs(r - 0.72)));
			astrolabe_rings = clamp(astrolabe_rings, 0.0, 1.0);
			float center_dot = 1.0 - smoothstep(0.04, 0.07, r);
			if (in_safe) {
				float safe_pulse = 0.5 + 0.5 * sin(TIME * 6.0 + r * 5.0);
				float s_glint = hz_pinpoint_star(p, 12.0, 0.72, TIME);
				col = mix(vec3(0.24, 0.92, 0.68), vec3(1.0, 0.92, 0.48), 0.48 + 0.24 * safe_pulse + s_glint * 0.25);
				alpha = (0.24 + 0.08 * safe_pulse + s_glint * 0.14 + outer_band * 0.65) * fade_out;
			} else {
				float gal_n = hz_fbm3(p * 3.0 + vec2(TIME * 0.07, -TIME * 0.05));
				float cel_neb = mix(gal_n, floor(gal_n * 5.0) / 5.0, 0.35);
				float spiral_v = sin(ang * 3.0 - log(max(r, 0.05)) * 4.5 - TIME * 1.4 + gal_n * 1.3);
				float vortex_arm = smoothstep(-0.15, 0.85, spiral_v) * (1.0 - r * 0.35);
				float hour_ticks = smoothstep(0.96, 0.992, abs(cos(ang * 6.0))) * smoothstep(0.76, 0.88, r);
				float min_ticks = smoothstep(0.90, 0.98, abs(cos(ang * 30.0))) * smoothstep(0.88, 0.92, r) * (1.0 - smoothstep(0.96, 0.99, r));
				float star_fleck = hz_pinpoint_star(p, 15.0, 0.74, TIME);
				float urgent = step(0.78, progress) * (0.5 + 0.5 * sin(TIME * 38.0));
				float danger_fill = step(r, max(0.18, progress));
				vec3 gal_col = mix(vec3(0.08, 0.06, 0.24), mix(vec3(0.24, 0.14, 0.48), hazard_color.rgb, cel_neb), 0.55 + 0.45 * vortex_arm);
				gal_col = mix(gal_col, mix(border_danger_color.rgb, vec3(1.0, 0.78, 0.36), 0.35), 0.42 * urgent + danger_fill * 0.22);
				gal_col = mix(gal_col, vec3(1.0, 0.90, 0.50), clamp(hour_ticks * 0.75 + min_ticks * 0.50 + astrolabe_rings * 0.65 + hand_trail * 0.52 + star_fleck * 0.85, 0.0, 1.0));
				col = gal_col;
				alpha = (0.34 + vortex_arm * 0.14 + danger_fill * 0.16 + dashed_rim * 0.92 + hour_ticks * 0.35 + min_ticks * 0.22 + astrolabe_rings * 0.25 + hand_trail * 0.26) * fade_out;
			}
			col = mix(col, vec3(1.0, 0.96, 0.60), clamp(wedge_edge + hand_line + center_dot, 0.0, 1.0));
			alpha = max(alpha, clamp((wedge_edge * 0.95 + hand_line * 0.95 + center_dot * 0.90) * fade_out, 0.0, 1.0));
		} else if (hazard_stage == 4) {
			float vortex = 0.5 + 0.5 * sin(ang * 6.0 + r * 14.0 - TIME * 7.5);
			float gust = smoothstep(0.65, 0.98, vortex) * (1.0 - smoothstep(0.86, 1.0, r));
			col = mix(vec3(0.46, 0.88, 1.0), vec3(0.92, 0.98, 1.0), gust * 0.72);
			col = mix(col, border_danger_color.rgb, clamp(dashed_rim * 0.95, 0.0, 1.0));
			alpha = (0.14 + gust * 0.24 + dashed_rim * 0.88) * fade_out;
		} else if (hazard_stage == 5) {
			float d_safe = length(p - safe_center_uv);
			bool in_safe = (d_safe <= safe_radius_uv);
			float safe_rim = 1.0 - smoothstep(0.005, 0.017, abs(d_safe - safe_radius_uv));
			float shrink_r = mix(safe_radius_uv * 2.15, safe_radius_uv, progress);
			float shrink_ring = (1.0 - smoothstep(0.004, 0.014, abs(d_safe - shrink_r))) * (1.0 - step(d_safe, safe_radius_uv));
			float loc_ang = atan(p.y - safe_center_uv.y, p.x - safe_center_uv.x) + TIME * 0.55;
			float perim_ticks = smoothstep(0.92, 0.99, abs(cos(loc_ang * 12.0))) * (1.0 - smoothstep(0.006, 0.016, abs(d_safe - safe_radius_uv * 0.86)));
			float s_len = length(safe_center_uv);
			float compass_glow = 0.0;
			if (s_len > 0.03) {
				vec2 s_dir = safe_center_uv / s_len;
				float proj = dot(p, s_dir);
				float perp = abs(p.x * s_dir.y - p.y * s_dir.x);
				float ray_mask = step(0.04, proj) * step(proj, max(0.05, s_len - safe_radius_uv)) * (1.0 - smoothstep(0.005, 0.015, perp));
				float chevron = 0.5 + 0.5 * sin((proj - TIME * 0.65) * 44.0);
				compass_glow = ray_mask * (0.48 + 0.52 * chevron);
			}
			float hand_ang = -1.5707963 + progress * 6.2831853;
			float hand_d = abs(atan(sin(ang - hand_ang), cos(ang - hand_ang)));
			float hand_line = (1.0 - smoothstep(0.007, 0.025, hand_d)) * step(0.05, r);
			float trail_diff = mod(hand_ang - ang + 6.2831853, 6.2831853);
			float hand_trail = (1.0 - smoothstep(0.0, 0.45, trail_diff)) * step(0.06, r) * step(r, 0.96);
			float hour_spokes = smoothstep(0.965, 0.994, abs(cos(ang * 6.0))) * step(0.08, r);
			float dial_rings = (1.0 - smoothstep(0.005, 0.014, abs(r - 0.34)))
				+ (1.0 - smoothstep(0.005, 0.014, abs(r - 0.68)))
				+ (1.0 - smoothstep(0.005, 0.014, abs(r - 0.96)));
			dial_rings = clamp(dial_rings, 0.0, 1.0);
			if (in_safe) {
				float s_pulse = 0.5 + 0.5 * sin(TIME * 6.0 + d_safe * 18.0);
				float c_glint = hz_pinpoint_star(p, 18.0, 0.70, TIME);
				col = mix(vec3(0.22, 0.94, 0.68), vec3(1.0, 0.92, 0.46), 0.45 + 0.30 * s_pulse + c_glint * 0.25);
				alpha = (0.28 + 0.10 * s_pulse + c_glint * 0.14) * fade_out;
			} else {
				float gal_e = hz_fbm3(p * 2.8 + vec2(TIME * 0.06, -TIME * 0.05));
				float cel_neb_e = mix(gal_e, floor(gal_e * 5.0) / 5.0, 0.35);
				float spiral_e = sin(ang * 2.0 - log(max(r, 0.04)) * 3.8 - TIME * 0.85 + gal_e * 1.5);
				float arm_e = smoothstep(-0.2, 0.85, spiral_e) * (1.0 - r * 0.40);
				float star_e = hz_pinpoint_star(p, 20.0, 0.72, TIME);
				float urgent = step(0.76, progress) * (0.5 + 0.5 * sin(TIME * 40.0));
				float danger_fill = step(r, max(0.14, progress));
				vec3 eclipse_col = mix(vec3(0.07, 0.05, 0.22), mix(vec3(0.24, 0.14, 0.48), hazard_color.rgb, cel_neb_e), 0.52 + 0.45 * arm_e);
				eclipse_col = mix(eclipse_col, mix(border_danger_color.rgb, vec3(1.0, 0.78, 0.36), 0.32), 0.40 * urgent + danger_fill * 0.20);
				eclipse_col = mix(eclipse_col, vec3(1.0, 0.90, 0.48), clamp(hour_spokes * 0.55 + dial_rings * 0.62 + hand_trail * 0.45 + star_e * 0.85, 0.0, 1.0));
				col = eclipse_col;
				alpha = (0.34 + arm_e * 0.12 + danger_fill * 0.16 + dashed_rim * 0.90 + hour_spokes * 0.26 + dial_rings * 0.28 + hand_trail * 0.24) * fade_out;
			}
			float gold_overlay = clamp(safe_rim + shrink_ring + perim_ticks * 0.85 + hand_line + compass_glow, 0.0, 1.0);
			col = mix(col, vec3(1.0, 0.95, 0.56), gold_overlay);
			alpha = max(alpha, clamp(gold_overlay * 0.95 * fade_out, 0.0, 1.0));
		} else {
			float swirl = sin(r * 14.0 - TIME * 4.2 + sin(ang * 4.0 + TIME * 2.0) * 1.6);
			float bubbles = smoothstep(0.72, 0.96, sin(p.x * 9.0 + TIME * 3.1) * cos(p.y * 9.0 - TIME * 2.7));
			vec3 dark_mire = hazard_color.rgb * 0.28 + vec3(0.14, 0.03, 0.18);
			col = mix(dark_mire, hazard_color.rgb, smoothstep(-0.4, 0.7, swirl) * 0.75 + bubbles * 0.45);
			col = mix(col, border_danger_color.rgb, clamp(dashed_rim, 0.0, 1.0));
			alpha = (0.54 + bubbles * 0.22 + dashed_rim * 0.94) * fade_out;
		}
	}

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
