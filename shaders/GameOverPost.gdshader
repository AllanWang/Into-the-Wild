shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float effect_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 scene_col = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float luma = dot(scene_col, vec3(0.299, 0.587, 0.114));
	vec3 gray = vec3(luma);

	vec2 centered = SCREEN_UV - vec2(0.5);
	float vignette = clamp(1.0 - dot(centered, centered) * 0.9, 0.42, 1.0);
	vec3 faded_gray = gray * mix(0.60, 0.38, 1.0 - vignette);

	vec3 final_col = mix(scene_col, faded_gray, clamp(effect_amount, 0.0, 1.0));
	COLOR = vec4(final_col, 1.0);
}
