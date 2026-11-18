// Stylized Toon Water / Lava / Cosmic / Anomaly Shader
// Adapted for Godot 4.x supporting both Perspective and Orthographic projection cameras.

shader_type spatial;
render_mode depth_draw_opaque, cull_disabled;

#include "res://shaders/clouds.gdshaderinc"

group_uniforms colors;
uniform vec4 shallow_color : source_color = vec4(0.32, 0.82, 0.92, 0.85);
uniform vec4 deep_color : source_color = vec4(0.06, 0.38, 0.72, 0.95);
uniform float depth_distance : hint_range(0.01, 10.0, 0.01) = 0.6;

group_uniforms foam;
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float foam_amount : hint_range(0.01, 2.0, 0.01) = 0.25;
uniform float foam_cutoff : hint_range(0.0, 1.0, 0.01) = 0.48;

group_uniforms biome_glow;
uniform float emission_strength : hint_range(0.0, 3.5, 0.01) = 0.0;
uniform vec4 secondary_foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool chromatic_foam = false;

group_uniforms surface_noise;
uniform sampler2D surface_noise : hint_default_white, repeat_enable;
uniform vec2 surface_noise_scale = vec2(0.4, 0.4);
uniform vec2 surface_noise_scroll1 = vec2(0.03, 0.02);
uniform vec2 surface_noise_scroll2 = vec2(-0.02, 0.03);
uniform float surface_noise_cutoff : hint_range(0.0, 1.0, 0.01) = 0.68;

group_uniforms waves;
uniform float wave_amplitude : hint_range(0.0, 0.5, 0.001) = 0.01;
uniform float wave_frequency : hint_range(0.1, 10.0, 0.1) = 1.5;
uniform float wave_speed : hint_range(0.0, 10.0, 0.1) = 1.2;

group_uniforms ripples;
const int ripple_count = 8;
uniform vec4[ripple_count] ripple_positions;
uniform float ripple_speed : hint_range(0.1, 5.0, 0.05) = 1.2;
uniform float ripple_ring_density : hint_range(1.0, 20.0, 0.5) = 7.0;

group_uniforms pool_shape;
uniform bool infinite_water = false;
uniform float edge_distortion_strength : hint_range(0.0, 1.5, 0.05) = 0.65;
uniform float edge_distortion_frequency : hint_range(0.1, 5.0, 0.1) = 1.2;

varying vec3 vertex_world;
varying vec2 uv_local;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(world_pos.x * wave_frequency + TIME * wave_speed) * cos(world_pos.z * wave_frequency + TIME * wave_speed);
	VERTEX.y += wave * wave_amplitude;
	vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	uv_local = UV;
}

void fragment() {
	vec2 p = vertex_world.xz;
	float angle = atan(vertex_world.z, vertex_world.x);

	float distort = sin(angle * 2.0) * 0.45 + cos(angle * 3.0 + 0.8) * 0.3 + sin(angle * 5.0) * 0.15;
	float pond_radius = 2.3 + distort;
	float dist_from_center = length(p);

	if (!infinite_water) {
		if (dist_from_center > pond_radius) {
			discard;
		}
	}
	ALPHA_SCISSOR_THRESHOLD = infinite_water ? 0.0 : 0.5;

	float edge_dist = infinite_water ? 1.0 : clamp(pond_radius - dist_from_center, 0.0, 1.8);
	float depth_factor = infinite_water ? 0.65 : smoothstep(0.0, depth_distance, edge_dist);
	float depth_stepped = floor(depth_factor * 3.0) / 3.0 * 0.45;
	vec4 water_color = mix(shallow_color, deep_color, depth_stepped);

	vec2 noise_uv1 = p * surface_noise_scale + surface_noise_scroll1 * TIME;
	vec2 noise_uv2 = p * surface_noise_scale + surface_noise_scroll2 * TIME;
	float n1 = texture(surface_noise, noise_uv1).r;
	float n2 = texture(surface_noise, noise_uv2).r;
	float noise_blended = (n1 + n2) * 0.5;

	float shore_band = 1.0 - clamp(edge_dist / foam_amount, 0.0, 1.0);
	float shore_foam = step(0.48, shore_band + noise_blended * 0.35) * step(0.02, shore_band);
	float surface_foam = step(surface_noise_cutoff, noise_blended) * (emission_strength > 0.2 ? 0.52 : 0.15);

	float total_foam = clamp(shore_foam + surface_foam, 0.0, 1.0);

	float ripple_foam = 0.0;
	for (int i = 0; i < 8; i++) {
		float current_radius = ripple_positions[i].w;
		float progress = ripple_positions[i].z;
		if (current_radius > 0.001) {
			vec2 delta_pos = p - ripple_positions[i].xy;
			float r_angle = atan(delta_pos.y, delta_pos.x);
			float rip_distort = sin(r_angle * 3.0) * 0.05 + cos(r_angle * 4.0 + 0.5) * 0.035;
			float d = length(delta_pos) + rip_distort;

			float ring_dist = abs(d - current_radius);
			float ring_thickness = 0.08 + progress * 0.05;
			float ring = smoothstep(ring_thickness, 0.0, ring_dist);

			float inner_radius = current_radius * 0.55;
			float inner_dist = abs(d - inner_radius);
			float inner_ring = smoothstep(0.06, 0.0, inner_dist) * 0.5;

			float life_fade = (1.0 - progress) * (1.0 - progress);
			ripple_foam += (ring + inner_ring) * life_fade * 0.85;
		}
	}
	total_foam = clamp(total_foam + ripple_foam, 0.0, 1.0);

	vec3 active_foam_rgb = foam_color.rgb;
	if (chromatic_foam) {
		float c_shift = 0.5 + 0.5 * sin(p.x * 0.12 + p.y * 0.15 + TIME * 0.8);
		active_foam_rgb = mix(foam_color.rgb, secondary_foam_color.rgb, step(0.5, c_shift));
	}

	vec3 final_rgb = mix(water_color.rgb, active_foam_rgb, total_foam);
	float final_alpha = infinite_water ? 1.0 : mix(water_color.a, foam_color.a, total_foam);

	ALBEDO = final_rgb;
	ALPHA = final_alpha;
	ROUGHNESS = 0.15;
	SPECULAR = 0.5;
	if (emission_strength > 0.001) {
		EMISSION = mix(water_color.rgb * 0.28, active_foam_rgb, total_foam) * emission_strength;
	}
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = clamp(NdotL + (ATTENUATION - 1.0), 0.0, 1.0);

	if (LIGHT_IS_DIRECTIONAL) {
		float light_value = get_cloud_noise(vertex_world);
		diffuse_amount = min(diffuse_amount, light_value);
	}

	float cuts_inv = 1.0 / 3.0;
	float stepped = clamp(ceil(diffuse_amount * 3.0) * cuts_inv, 0.2, 1.0);

	vec3 diffuse = ALBEDO.rgb * LIGHT_COLOR / PI;
	diffuse *= stepped;
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
}
