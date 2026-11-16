shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 fill_color : source_color = vec4(0.95, 0.28, 0.32, 0.96);
uniform vec4 bg_color : source_color = vec4(0.05, 0.07, 0.11, 0.86);
uniform vec4 border_color : source_color = vec4(0.92, 0.89, 0.84, 0.38);

instance uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Camera-facing billboard preserving per-instance X/Y scale (MODEL_MATRIX[0]/[1] lengths)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	float r = clamp(fill_ratio, 0.0, 1.0);
	bool is_border = (UV.x < 0.025 || UV.x > 0.975 || UV.y < 0.14 || UV.y > 0.86);
	vec4 col = (UV.x <= r) ? fill_color : bg_color;
	if (is_border) {
		col = mix(col, border_color, 0.55);
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
