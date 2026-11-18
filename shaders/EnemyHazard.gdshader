shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 hazard_color : source_color = vec4(1.0, 0.20, 0.28, 1.0);
uniform vec4 border_danger_color : source_color = vec4(1.0, 0.12, 0.20, 1.0);
uniform float inner_ratio : hint_range(0.0, 0.95) = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform int hazard_stage = 0; // 0=Telegraph, 1=Quake Eruption, 2=Active Acid Pool, 3=Clock-Dial, 4=Whiteout Storm
uniform float fade_out : hint_range(0.0, 1.0) = 1.0;
uniform float safe_angle = 0.0;
uniform float safe_half_width = 0.567;

void fragment() {
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

	vec3 col = hazard_color.rgb;
	float alpha = 0.0;

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
		float wedge_edge = (1.0 - smoothstep(0.015, 0.055, edge_dist)) * step(0.06, r);
		float hand_ang = safe_angle + 3.14159265 + progress * 6.2831853;
		float hand_d = abs(atan(sin(ang - hand_ang), cos(ang - hand_ang)));
		float hand_line = (1.0 - smoothstep(0.012, 0.042, hand_d)) * step(0.05, r);
		float center_dot = 1.0 - smoothstep(0.05, 0.08, r);
		if (in_safe) {
			float safe_pulse = 0.5 + 0.5 * sin(TIME * 6.0 + r * 5.0);
			col = mix(vec3(0.28, 0.92, 0.68), vec3(1.0, 0.90, 0.44), 0.55 + 0.25 * safe_pulse);
			alpha = (0.24 + 0.08 * safe_pulse + outer_band * 0.65) * fade_out;
		} else {
			float hour_ticks = smoothstep(0.95, 0.99, abs(cos(ang * 6.0))) * smoothstep(0.75, 0.88, r);
			float urgent = step(0.78, progress) * (0.5 + 0.5 * sin(TIME * 38.0));
			float danger_fill = step(r, max(0.18, progress));
			col = mix(hazard_color.rgb, border_danger_color.rgb, 0.55 + 0.40 * urgent);
			col = mix(col, vec3(1.0, 0.88, 0.42), hour_ticks * 0.45);
			alpha = (0.20 + danger_fill * 0.16 + dashed_rim * 0.95 + hour_ticks * 0.25) * fade_out;
		}
		col = mix(col, vec3(1.0, 0.95, 0.58), clamp(wedge_edge + hand_line + center_dot, 0.0, 1.0));
		alpha = max(alpha, clamp((wedge_edge * 0.95 + hand_line * 0.95 + center_dot * 0.90) * fade_out, 0.0, 1.0));
	} else if (hazard_stage == 4) {
		float vortex = 0.5 + 0.5 * sin(ang * 6.0 + r * 14.0 - TIME * 7.5);
		float gust = smoothstep(0.65, 0.98, vortex) * (1.0 - smoothstep(0.86, 1.0, r));
		col = mix(vec3(0.46, 0.88, 1.0), vec3(0.92, 0.98, 1.0), gust * 0.72);
		col = mix(col, border_danger_color.rgb, clamp(dashed_rim * 0.95, 0.0, 1.0));
		alpha = (0.14 + gust * 0.24 + dashed_rim * 0.88) * fade_out;
	} else {
		float swirl = sin(r * 14.0 - TIME * 4.2 + sin(ang * 4.0 + TIME * 2.0) * 1.6);
		float bubbles = smoothstep(0.72, 0.96, sin(p.x * 9.0 + TIME * 3.1) * cos(p.y * 9.0 - TIME * 2.7));
		vec3 dark_mire = hazard_color.rgb * 0.28 + vec3(0.14, 0.03, 0.18);
		col = mix(dark_mire, hazard_color.rgb, smoothstep(-0.4, 0.7, swirl) * 0.75 + bubbles * 0.45);
		col = mix(col, border_danger_color.rgb, clamp(dashed_rim, 0.0, 1.0));
		alpha = (0.54 + bubbles * 0.22 + dashed_rim * 0.94) * fade_out;
	}

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
