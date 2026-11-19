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
uniform bool cosmic_void = false;

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
uniform bool enable_cloud_shadows = true;
uniform float edge_distortion_strength : hint_range(0.0, 1.5, 0.05) = 0.65;
uniform float edge_distortion_frequency : hint_range(0.1, 5.0, 0.1) = 1.2;

varying vec3 vertex_world;
varying vec2 uv_local;

vec2 cw_hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}

float cw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cw_fbm3(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += amp * cw_noise(p);
		p = rot * p * 2.03 + vec2(9.1, 4.7);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(world_pos.x * wave_frequency + TIME * wave_speed) * cos(world_pos.z * wave_frequency + TIME * wave_speed);
	VERTEX.y += wave * wave_amplitude;
	vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	uv_local = UV;
}

void fragment() {
	vec2 p = vertex_world.xz;
	float edge_dist = 1.0;
	if (!infinite_water) {
		float angle = atan(vertex_world.z, vertex_world.x);
		float distort = sin(angle * 2.0) * 0.45 + cos(angle * 3.0 + 0.8) * 0.3 + sin(angle * 5.0) * 0.15;
		float pond_radius = 2.3 + distort;
		float dist_from_center = length(p);
		if (dist_from_center > pond_radius) {
			discard;
		}
		edge_dist = clamp(pond_radius - dist_from_center, 0.0, 1.8);
	}
	ALPHA_SCISSOR_THRESHOLD = infinite_water ? 0.0 : 0.5;

	if (cosmic_void) {
		float nb1 = cw_fbm3(p * 0.032 + vec2(TIME * 0.010, -TIME * 0.007));
		float nb2 = cw_fbm3(p * 0.058 + vec2(13.7, 4.2) + vec2(nb1 * 1.2));
		float cel_n = mix(nb2, floor(nb2 * 4.0) / 4.0, 0.30);
		vec3 void_base = mix(deep_color.rgb, vec3(0.022, 0.024, 0.075), 0.75);
		vec3 void_neb = mix(void_base, vec3(0.055, 0.048, 0.145), smoothstep(0.32, 0.72, cel_n));

		// Razor-sharp deep space starfield
		vec2 su1 = p * 1.45;
		vec2 id1 = floor(su1);
		float pk1 = fract(sin(dot(id1, vec2(91.7, 213.9))) * 43758.5453);
		float s1 = 0.0;
		if (pk1 > 0.64) {
			vec2 off1 = vec2(0.18) + 0.64 * cw_hash22(id1);
			float d1 = length(fract(su1) - off1);
			float tw1 = 0.65 + 0.35 * sin(TIME * 2.4 + pk1 * 30.0);
			s1 = (1.0 - smoothstep(0.015, 0.055, d1)) * tw1;
		}
		vec2 su2 = p * 0.65 + vec2(17.1, 8.9);
		vec2 id2 = floor(su2);
		float pk2 = fract(sin(dot(id2, vec2(47.3, 159.1))) * 43758.5453);
		float s2 = 0.0;
		if (pk2 > 0.74) {
			vec2 off2 = vec2(0.20) + 0.60 * cw_hash22(id2 + vec2(3.1, 6.7));
			float d2 = length(fract(su2) - off2);
			float tw2 = 0.70 + 0.30 * sin(TIME * 3.1 + pk2 * 22.0);
			s2 = (1.0 - smoothstep(0.010, 0.038, d2)) * tw2;
		}
		vec3 s1_col = mix(vec3(0.86, 0.92, 1.0), secondary_foam_color.rgb, step(0.82, pk1));
		vec3 star_glow = s1_col * s1 * 0.85 + foam_color.rgb * s2 * 0.92;
		vec3 void_rgb = clamp(void_neb + star_glow, vec3(0.0), vec3(1.0));
		ALBEDO = void_rgb;
		// Keep infinite void opaque; island pond gets edge fade
		ALPHA = infinite_water ? 1.0 : clamp(edge_dist, 0.0, 1.0);
		ROUGHNESS = 0.3;
		SPECULAR = 0.2;
		EMISSION = (void_neb * 0.35 + star_glow * 0.95) * max(0.55, emission_strength);
	} else {
		float depth_factor = infinite_water ? 0.65 : smoothstep(0.0, depth_distance, edge_dist);
		float depth_stepped = floor(depth_factor * 3.0) / 3.0 * 0.45;
		vec4 water_color = mix(shallow_color, deep_color, depth_stepped);

		vec2 noise_uv1 = p * surface_noise_scale + surface_noise_scroll1 * TIME;
		vec2 noise_uv2 = p * surface_noise_scale + surface_noise_scroll2 * TIME;
		float n1 = texture(surface_noise, noise_uv1).r;
		float n2 = texture(surface_noise, noise_uv2).r;
		float noise_blended = (n1 + n2) * 0.5;

		float shore_band = infinite_water ? 0.0 : (1.0 - clamp(edge_dist / foam_amount, 0.0, 1.0));
		float shore_foam = infinite_water ? 0.0 : (step(0.48, shore_band + noise_blended * 0.35) * step(0.02, shore_band));
		float surface_foam = step(surface_noise_cutoff, noise_blended) * (emission_strength > 0.2 ? 0.52 : 0.15);

		float total_foam = clamp(shore_foam + surface_foam, 0.0, 1.0);

		if (!infinite_water) {
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
		}

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
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = clamp(NdotL + (ATTENUATION - 1.0), 0.0, 1.0);

	if (LIGHT_IS_DIRECTIONAL && enable_cloud_shadows) {
		float light_value = get_cloud_noise(vertex_world);
		diffuse_amount = min(diffuse_amount, light_value);
	}

	float cuts_inv = 1.0 / 3.0;
	float stepped = clamp(ceil(diffuse_amount * 3.0) * cuts_inv, 0.2, 1.0);

	vec3 diffuse = ALBEDO.rgb * LIGHT_COLOR / PI;
	diffuse *= stepped;
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
}
