// MIT License. 
// Made by Dylearn
// Adapted from atzuk4451 https://godotshaders.com/shader/flexible-toon-shader-godot-4/

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

group_uniforms lighting;
uniform int cuts : hint_range(1, 8) = 3;
uniform float wrap : hint_range(-2.0f, 2.0f) = 0.0f;
uniform float steepness : hint_range(1.0f, 8.0f) = 1.0f;

varying vec3 vertex_pos;
varying vec3 normal;
varying vec3 vertex_world;

#include "res://shaders/clouds.gdshaderinc"

void vertex() {
	vertex_pos = VERTEX;
	normal = NORMAL;
	vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

group_uniforms water_bank;
uniform vec3 water_pool_center = vec3(0.0, 0.0, 0.0);
uniform float water_pool_radius = 3.5;
uniform vec4 bank_color : source_color = vec4(0.55, 0.62, 0.35, 1.0);
uniform float bank_width = 0.45;

group_uniforms grass_edge;
uniform bool enable_grass_edge = true;
uniform float grass_edge_frequency : hint_range(1.0, 30.0, 0.5) = 7.0;
uniform float grass_edge_height : hint_range(0.0, 1.0, 0.01) = 0.36;
uniform float grass_edge_irregularity : hint_range(0.0, 1.0, 0.05) = 0.85;
uniform float grass_edge_clumping : hint_range(0.0, 1.0, 0.05) = 0.75;

float get_organic_grass_tooth(float screen_x, float freq, float max_height, float irreg, float clumping) {
	float coord = screen_x * freq;
	int cell0 = int(floor(coord));
	float max_tooth = 0.0;

	// Loop over neighboring cells to allow blades to jitter, overlap, and form natural clumps
	for (int k = cell0 - 2; k <= cell0 + 2; k++) {
		float fk = float(k);
		// Pseudo-random values from seed
		float r1 = fract(sin(fk * 127.1 + 311.7) * 43758.5453);
		float r2 = fract(sin(fk * 269.5 + 183.3) * 43758.5453);
		float r3 = fract(sin(fk * 419.2 + 371.9) * 43758.5453);
		float r4 = fract(sin(fk * 83.7 + 91.1) * 43758.5453);

		// Clumping wave: creates tuft groupings (2-4 blades) separated by smooth gaps
		float clump_wave = sin(fk * 0.52) * 0.45 + sin(fk * 0.21 + 1.1) * 0.35 + 0.3;
		// Threshold: when clump is below 0.1, no grass tuft spawns -> smooth ground
		if (clump_wave < 0.08 * clumping) {
			continue;
		}
		float clump = mix(1.0, clamp(clump_wave, 0.0, 1.3), clumping);

		// Natural sporadic skip
		if (r1 < 0.22 * irreg) {
			continue;
		}

		// Jittered blade center position
		float center = fk + 0.5 + (r2 - 0.5) * 0.75 * irreg;

		// Varied blade width & height
		float blade_w = mix(0.28, 0.65, mix(0.5, r3, irreg));
		float blade_h = mix(0.45, 1.35, pow(r4, 1.3)) * clump;

		// Asymmetric lean
		float lean = (fract(sin(fk * 19.3 + 7.7) * 43758.5453) - 0.5) * 0.3 * irreg;

		// Primary blade profile
		float u = (coord - center) / blade_w + lean;
		if (abs(u) < 1.0) {
			float p = pow(1.0 - abs(u), mix(1.5, 2.2, r2));
			float t = p * blade_h * max_height;
			max_tooth = max(max_tooth, t);
		}

		// Secondary companion blade (forming natural double/triple tufts)
		if (r3 > 0.3) {
			float twin_center = center + (r1 - 0.5) * 0.5 * irreg;
			float twin_w = blade_w * mix(0.55, 0.85, r4);
			float twin_h = blade_h * mix(0.4, 0.82, r2);
			float u_twin = (coord - twin_center) / twin_w;
			if (abs(u_twin) < 1.0) {
				float p_twin = pow(1.0 - abs(u_twin), 1.6);
				float t_twin = p_twin * twin_h * max_height;
				max_tooth = max(max_tooth, t_twin);
			}
		}
	}

	return max_tooth;
}

void fragment() {
	vec3 sample_world = vertex_world;
	if (enable_grass_edge) {
		float screen_x = dot(vertex_world, INV_VIEW_MATRIX[0].xyz);
		float tooth = get_organic_grass_tooth(screen_x, grass_edge_frequency, grass_edge_height, grass_edge_irregularity, grass_edge_clumping);
		sample_world -= INV_VIEW_MATRIX[1].xyz * tooth;
	}

	// Texture noises for grass patches
	float albedo2_noise_tex = texture(albedo2_noise, sample_world.xz * (albedo2_scale)).r;
	float albedo3_noise_tex = texture(albedo3_noise, sample_world.xz * (albedo3_scale)).r;
	// Set colours based on noise thresholds
	ALBEDO = albedo1.rgb;
	if (albedo2_noise_tex > albedo2_threshold) {
		ALBEDO = albedo2.rgb;
	} if (albedo3_noise_tex > albedo3_threshold) {
		ALBEDO = albedo3.rgb;
	}

	// Subtle, harmonious shore transition around the organic pool
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
}

void light() {
	// Diffuse lighting.
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = NdotL + (ATTENUATION - 1.0) + wrap;
	diffuse_amount *= steepness;

	// CLOUDS
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 vertex_world_pos = (MODEL_MATRIX * vec4(vertex_pos, 1.0)).xyz;
		float light_value = get_cloud_noise(vertex_world_pos);
		diffuse_amount = min(diffuse_amount, light_value);
	}

	// Toon Shading
	float cuts_inv = 1.0f / float(cuts);
	float cut = cuts_inv; // single cut width
	float original_index = ceil(diffuse_amount * float(cuts));   // ceil(diffuse * cuts)
	float original_stepped = clamp(original_index * cut, 0.0, 1.0);
	float diffuse_stepped = clamp(diffuse_amount + mod(1.0f - diffuse_amount, cuts_inv), 0.0f, 1.0f);

	diffuse_stepped = original_stepped;
	vec3 diffuse = ALBEDO.rgb * LIGHT_COLOR / PI;
	diffuse *= diffuse_stepped;
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
}