shader_type spatial;
render_mode unshaded, blend_mix;

uniform vec4 base_color : source_color = vec4(1.0, 0.86, 0.35, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.96, 0.75, 1.0);
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.5;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - n_dot_v, fresnel_power);
	ALBEDO = mix(base_color.rgb, rim_color.rgb, fresnel * rim_strength);
}
