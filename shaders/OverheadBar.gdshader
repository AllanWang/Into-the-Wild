shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

uniform vec4 fill_color : source_color = vec4(0.95, 0.28, 0.32, 0.96);
uniform vec4 bg_color : source_color = vec4(0.05, 0.07, 0.11, 0.86);
uniform vec4 border_color : source_color = vec4(0.92, 0.89, 0.84, 0.38);

uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float armor_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float stock_pips : hint_range(1.0, 5.0) = 1.0;
uniform float impervious_ratio : hint_range(0.0, 1.0) = 0.0;

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
	float arm = clamp(armor_ratio, 0.0, 1.0);
	float imp = clamp(impervious_ratio, 0.0, 1.0);
	float segs = clamp(floor(stock_pips + 0.5), 1.0, 5.0);

	bool is_border = (UV.x < 0.025 || UV.x > 0.975 || UV.y < 0.14 || UV.y > 0.86);
	vec4 col = (UV.x <= r) ? fill_color : bg_color;

	if (arm > 0.005 && UV.x <= arm) {
		col = mix(col, vec4(1.0, 0.80, 0.20, 0.98), 0.94);
	}

	if (segs > 1.5 && UV.x > 0.04 && UV.x < 0.96) {
		float seg_pos = UV.x * segs;
		float dist_tick = min(fract(seg_pos), 1.0 - fract(seg_pos));
		if (dist_tick < 0.024 * segs) {
			col = mix(col, vec4(0.02, 0.03, 0.06, 0.96), 0.85);
		}
	}

	if (imp > 0.01) {
		col = mix(col, vec4(1.0, 0.95, 0.68, 0.98), imp * 0.82);
	}

	if (is_border) {
		vec4 b_col = border_color;
		if (imp > 0.01) {
			b_col = vec4(1.0, 0.94, 0.56, 0.96);
		} else if (arm > 0.005) {
			b_col = vec4(1.0, 0.84, 0.34, 0.90);
		}
		col = mix(col, b_col, 0.62);
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
