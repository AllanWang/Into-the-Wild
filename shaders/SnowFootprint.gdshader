shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 print_color : source_color = vec4(0.32, 0.54, 0.78, 1.0);
uniform vec4 rim_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform float base_opacity : hint_range(0.0, 1.0) = 0.42;

instance uniform float fade_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float taper = 1.0 - 0.10 * p.y;
	vec2 q = vec2(p.x / max(0.55, taper), p.y);
	vec2 seg_p = vec2(q.x, q.y - clamp(q.y, -0.32, 0.32));
	float d = length(seg_p) / 0.62;

	float inner = 1.0 - smoothstep(0.25, 1.0, d);
	float rim = smoothstep(0.70, 0.92, d) * (1.0 - smoothstep(0.92, 1.16, d));

	vec3 col = mix(print_color.rgb, rim_color.rgb, rim * 0.30);
	float alpha = (inner * base_opacity + rim * base_opacity * 0.22) * clamp(fade_alpha, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
