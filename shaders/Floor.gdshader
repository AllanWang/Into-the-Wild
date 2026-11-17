// MIT License.
// Made by Dylearn — Extended with Painterly Shape of Dreams x Arcane Biome FX

shader_type spatial;

group_uniforms colour;
uniform vec4 albedo1 : source_color = vec4(1.0f);

group_uniforms colour.albedo2;
uniform vec4 albedo2 : source_color = vec4(1.0f);
uniform sampler2D albedo2_noise;
uniform float albedo2_scale : hint_range(0.0, 1.0, 0.001) = 0.005;
uniform float albedo2_threshold : hint_range(0.0, 1.0, 0.001) = 0.604;

group_uniforms colour.albedo3;
uniform vec4 albedo3 : source_color = vec4(1.0f);
uniform sampler2D albedo3_noise;
uniform float albedo3_scale : hint_range(0.0, 0.1, 0.001) = 0.003;
uniform float albedo3_threshold : hint_range(0.0, 1.0, 0.001) = 0.661;
uniform vec2 noise_offset = vec2(0.0);

group_uniforms lighting;
uniform int cuts : hint_range(1, 8) = 3;
uniform float wrap : hint_range(-2.0f, 2.0f) = 0.0f;
uniform float steepness : hint_range(1.0f, 8.0f) = 1.0f;

group_uniforms water_bank;
uniform vec3 water_pool_center = vec3(0.0, 0.0, 0.0);
uniform float water_pool_radius = 3.5;
uniform vec4 bank_color : source_color = vec4(0.55, 0.62, 0.35, 1.0);
uniform float bank_width = 0.45;

group_uniforms biome_fx;
uniform int biome_fx_mode = 0; // 0=Meadow, 1=Frost, 2=Constellation, 3=Lava, 4=Arcane Anomaly
uniform vec4 fx_color1 : source_color = vec4(0.55, 0.92, 1.0, 1.0);
uniform vec4 fx_color2 : source_color = vec4(1.0, 0.36, 0.78, 1.0);
uniform vec4 fx_color3 : source_color = vec4(1.0, 0.88, 0.48, 1.0);
uniform float fx_emission_strength : hint_range(0.0, 4.0, 0.01) = 0.0;

varying vec3 vertex_pos;
varying vec3 normal;
varying vec3 vertex_world;

#include "res://shaders/clouds.gdshaderinc"

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(0.0001, dot(ba, ba)), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	vertex_pos = VERTEX;
	normal = NORMAL;
	vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float albedo2_noise_tex = texture(albedo2_noise, (vertex_world.xz + noise_offset) * (albedo2_scale)).r;
	float albedo3_noise_tex = texture(albedo3_noise, (vertex_world.xz + noise_offset) * (albedo3_scale)).r;

	ALBEDO = albedo1.rgb;
	if (albedo2_noise_tex > albedo2_threshold) {
		ALBEDO = albedo2.rgb;
	}
	if (albedo3_noise_tex > albedo3_threshold) {
		ALBEDO = albedo3.rgb;
	}

	vec3 emissive = vec3(0.0);

	if (biome_fx_mode == 1) {
		// Glacial Frostfield: crisp stepped frost fractures & diamond ice glint
		float crack_a = 1.0 - smoothstep(0.004, 0.018, abs(albedo2_noise_tex - 0.50));
		float crack_b = 1.0 - smoothstep(0.003, 0.014, abs(albedo3_noise_tex - 0.54));
		float frost_line = clamp(crack_a + crack_b * 0.7, 0.0, 1.0);
		ALBEDO = mix(ALBEDO, fx_color1.rgb, frost_line * 0.65);
		emissive = fx_color1.rgb * frost_line * fx_emission_strength;
	} else if (biome_fx_mode == 2) {
		// Astral Constellation: nebula swirls + starlight nodes + golden/cyan constellation threads
		vec2 uv_star = vertex_world.xz * 0.34;
		vec2 cell = floor(uv_star);
		vec2 f = fract(uv_star);
		vec2 star_p = 0.22 + 0.56 * hash22(cell);
		float d_star = length(f - star_p);
		float twinkle = 0.72 + 0.28 * sin(TIME * 2.4 + cell.x * 3.1 + cell.y * 5.7);
		float star_core = smoothstep(0.055, 0.010, d_star) * twinkle;

		// Connect a subset of neighboring cells with crisp constellation lines
		vec2 right_p = vec2(1.0, 0.0) + 0.22 + 0.56 * hash22(cell + vec2(1.0, 0.0));
		vec2 up_p = vec2(0.0, 1.0) + 0.22 + 0.56 * hash22(cell + vec2(0.0, 1.0));
		float h_pick = hash22(cell + vec2(7.3, 2.9)).x;
		float line_mask = 0.0;
		if (h_pick > 0.42) {
			line_mask = max(line_mask, smoothstep(0.020, 0.005, seg_dist(f, star_p, right_p)));
		}
		if (h_pick > 0.24 && h_pick < 0.78) {
			line_mask = max(line_mask, smoothstep(0.020, 0.005, seg_dist(f, star_p, up_p)));
		}
		vec3 star_col = mix(fx_color1.rgb, fx_color3.rgb, step(0.5, h_pick));
		ALBEDO = mix(ALBEDO, star_col, clamp(line_mask * 0.55 + star_core, 0.0, 1.0));
		emissive = (fx_color1.rgb * line_mask * 0.55 + star_col * star_core * 1.45) * fx_emission_strength;
	} else if (biome_fx_mode == 3) {
		// Volcanic Caldera: stepped toon magma fissures across dark obsidian plates
		float fissure = 1.0 - smoothstep(0.006, 0.036, abs(albedo2_noise_tex - 0.49));
		float hot_core = 1.0 - smoothstep(0.0, 0.013, abs(albedo2_noise_tex - 0.49));
		float pulse = 0.84 + 0.16 * sin(TIME * 2.2 + vertex_world.x * 0.35 + vertex_world.z * 0.28);
		vec3 lava_col = mix(fx_color2.rgb, fx_color1.rgb, hot_core);
		ALBEDO = mix(ALBEDO, lava_col, fissure * 0.92);
		emissive = lava_col * fissure * pulse * fx_emission_strength;
	} else if (biome_fx_mode == 4) {
		// Arcane Anomaly: painterly oil-slick chromatic bands + glowing Hextech/Shimmer fractal veins
		float swirl = sin(albedo2_noise_tex * 15.0 + albedo3_noise_tex * 11.0 + TIME * 0.55);
		float cel_band = floor((swirl * 0.5 + 0.5) * 4.0) / 4.0;
		vec3 oil_tint = mix(fx_color1.rgb, fx_color2.rgb, cel_band);
		oil_tint = mix(oil_tint, fx_color3.rgb, step(0.74, cel_band) * 0.65);
		ALBEDO = mix(ALBEDO, ALBEDO * 0.65 + oil_tint * 0.38, 0.55);

		float vein1 = 1.0 - smoothstep(0.004, 0.022, abs(albedo2_noise_tex - 0.51));
		float vein2 = 1.0 - smoothstep(0.003, 0.018, abs(albedo3_noise_tex - 0.47));
		float vein = clamp(vein1 + vein2 * 0.85, 0.0, 1.0);
		vec3 vein_col = mix(fx_color1.rgb, fx_color2.rgb, 0.5 + 0.5 * sin(vertex_world.x * 0.18 - vertex_world.z * 0.15 + TIME * 0.9));
		vein_col = mix(vein_col, fx_color3.rgb, step(0.82, vein));
		ALBEDO = mix(ALBEDO, vein_col, vein * 0.88);
		emissive = (vein_col * vein * 1.15 + oil_tint * 0.10) * fx_emission_strength;
	}

	if (water_pool_radius > 0.0) {
		float angle = atan(vertex_world.z - water_pool_center.z, vertex_world.x - water_pool_center.x);
		float distort = sin(angle * 2.0) * 0.45 + cos(angle * 3.0 + 0.8) * 0.3 + sin(angle * 5.0) * 0.15;
		float dynamic_radius = 2.3 + distort;
		float dist = distance(vertex_world.xz, water_pool_center.xz);
		if (dist >= dynamic_radius - 0.1 && dist < dynamic_radius + bank_width) {
			float bank_factor = smoothstep(dynamic_radius - 0.1, dynamic_radius + bank_width, dist);
			ALBEDO = mix(bank_color.rgb, ALBEDO, bank_factor);
		}
	}

	EMISSION = emissive;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = NdotL + (ATTENUATION - 1.0) + wrap;
	diffuse_amount *= steepness;

	if (LIGHT_IS_DIRECTIONAL) {
		vec3 vertex_world_pos = (MODEL_MATRIX * vec4(vertex_pos, 1.0)).xyz;
		float light_value = get_cloud_noise(vertex_world_pos);
		diffuse_amount = min(diffuse_amount, light_value);
	}

	float cuts_inv = 1.0f / float(cuts);
	float cut = cuts_inv;
	float original_index = ceil(diffuse_amount * float(cuts));
	float original_stepped = clamp(original_index * cut, 0.0, 1.0);

	vec3 diffuse = ALBEDO.rgb * LIGHT_COLOR / PI;
	diffuse *= original_stepped;
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
}
