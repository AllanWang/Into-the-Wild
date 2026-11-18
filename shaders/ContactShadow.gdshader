shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 shadow_color : source_color = vec4(0.02, 0.05, 0.08, 0.42);

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r2 = dot(d, d);
	if (r2 > 1.0) {
		discard;
	}
	float falloff = 1.0 - r2;
	ALBEDO = shadow_color.rgb;
	ALPHA = shadow_color.a * falloff * falloff;
}
