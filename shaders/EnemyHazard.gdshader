shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 hazard_color : source_color = vec4(1.0, 0.20, 0.28, 1.0);
uniform vec4 border_danger_color : source_color = vec4(1.0, 0.12, 0.20, 1.0);
uniform float inner_ratio : hint_range(0.0, 0.95) = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform int hazard_stage = 0; // 0=Telegraph, 1=Quake Eruption, 2=Active Acid Pool
uniform float fade_out : hint_range(0.0, 1.0) = 1.0;

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
