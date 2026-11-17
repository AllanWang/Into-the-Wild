shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 groove_color : source_color = vec4(0.14, 0.20, 0.32, 1.0);
uniform vec4 edge_color : source_color = vec4(0.62, 0.75, 0.90, 1.0);
uniform float segment_opacity : hint_range(0.0, 0.5) = 0.065;

instance uniform float fade_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float ax = abs(p.x);
	float ay = abs(p.y);
	if (ax > 0.98 || ay > 0.98) {
		discard;
	}
	// Smooth longitudinal feathering so closely spaced stamps merge into one continuous track with zero steps!
	float along = cos(ay * 1.5707963);
	along = along * along;
	float trough = 1.0 - smoothstep(0.38, 0.84, ax);
	float berm = smoothstep(0.66, 0.84, ax) * (1.0 - smoothstep(0.84, 0.98, ax));

	vec3 col = mix(groove_color.rgb, edge_color.rgb, berm * 0.45);
	float alpha = (trough * segment_opacity + berm * segment_opacity * 0.35) * along * clamp(fade_alpha, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
