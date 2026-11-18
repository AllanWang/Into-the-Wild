// MIT License.
// Made by Dylearn — Extended with Painterly Tip Glow, Biome Density & Arcane Iridescence

shader_type spatial;
render_mode depth_draw_opaque;

#include "res://shaders/clouds.gdshaderinc"

group_uniforms colours_and_textures;
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 albedo1 : source_color = vec4(1.0f);

	group_uniforms colours_and_textures.albedo2;
uniform vec4 albedo2 : source_color = vec4(1.0f);
uniform float albedo2_scale : hint_range(0.0, 1.0, 0.001) = 0.005;
uniform float albedo2_threshold : hint_range(0.0, 1.0, 0.001) = 0.604;
uniform sampler2D albedo2_noise;

	group_uniforms colours_and_textures.albedo3;
uniform vec4 albedo3 : source_color = vec4(1.0f);
uniform float albedo3_scale : hint_range(0.0, 0.1, 0.001) = 0.003;
uniform float albedo3_threshold : hint_range(0.0, 1.0, 0.001) = 0.661;
uniform sampler2D albedo3_noise;
uniform vec2 noise_offset = vec2(0.0);

	group_uniforms colours_and_textures.accent1;
uniform float accent_frequency1 : hint_range(0.0, 0.05, 0.0001) = 0.001;
uniform sampler2D accent_texture1 : source_color, filter_nearest;
uniform vec4 accent_albedo1 : source_color = vec4(1.0f);
uniform float accent_height1 : hint_range(0.0, 1.0, 0.001) = 0.5;
uniform float accent_scale1 : hint_range(0.0, 2.0, 0.001) = 1.0;

	group_uniforms colours_and_textures.accent2;
uniform float accent_probability2 : hint_range(0.0, 0.05, 0.0001) = 0.1;
uniform sampler2D accent_texture2 : source_color, filter_nearest;
uniform vec4 accent_albedo2 : source_color = vec4(1.0f);
uniform float accent_height2 : hint_range(0.0, 1.0, 0.001) = 0.5;
uniform float accent_scale2 : hint_range(0.0, 2.0, 0.001) = 1.0;

group_uniforms biome_tip_fx;
uniform bool web_fast_mode = false;
uniform float blade_density : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float blade_scale : hint_range(0.2, 1.5, 0.01) = 1.0;
uniform vec4 tip_emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float tip_emission_strength : hint_range(0.0, 3.0, 0.01) = 0.0;
uniform bool anomaly_iridescence = false;

group_uniforms water_exclusion;
uniform vec3 water_pool_center = vec3(0.0, 0.0, 0.0);
uniform float water_pool_radius = 4.2;

group_uniforms animation;
uniform float framerate = 5.0;
uniform bool quantised = true;
	group_uniforms animation.world_space;
uniform bool world_space_sway = true;
uniform bool debug_noise = false;
uniform float world_sway_angle : hint_range(0.0f, 180.0f) = 60.0;
uniform float fake_perspective_scale : hint_range(-0.15, 0.6, 0.001) = 0.3;
uniform sampler2D wind_noise;
uniform float wind_noise_threshold : hint_range(-1.0, 1.0, 0.001) = 0.365;
uniform float wind_noise_scale : hint_range(0.0, 0.1, 0.001) = 0.071;
uniform float wind_noise_speed : hint_range(0.0, 0.2, 0.001) = 0.025;
uniform vec2 wind_noise_direction = vec2(0.0, 1.0);
uniform float noise_diverge_angle : hint_range(0.0, 45.0, 0.001) = 10.0;
	group_uniforms animation.view_space;
uniform bool view_space_sway = true;
uniform float view_sway_speed : hint_range(0.0f, 5.0f) = 0.1;
uniform float view_sway_angle : hint_range(0.0f, 45.0f) = 10.0;
	group_uniforms character_displacement;
uniform bool character_displacement = true;
uniform bool debug_displacement = false;
uniform float player_displacement_angle_z : hint_range(0.0, 360.0, 0.1) = 45.0;
uniform float player_displacement_angle_x : hint_range(0.0, 360.0, 0.1) = 45.0;
uniform float radius_exponent : hint_range(0.0, 10.0, 0.001) = 1.0;
const int character_count = 64;
uniform vec4[character_count] character_positions;
uniform int active_character_count = 0;

group_uniforms lighting;
uniform int cuts : hint_range(1, 8) = 3;
uniform float wrap : hint_range(-2.0f, 2.0f) = 0.0f;
uniform float steepness : hint_range(1.0f, 8.0f) = 1.0f;
uniform float threshold_gradient_size = 0.2;

varying float debug_wind_color;
varying vec3 debug_interactive_color;
varying float wind_noise_sample;

varying float instance_id;
varying float id_seed1;
varying float id_seed2;

varying vec3 model_origin;
varying vec3 object_origin;
varying vec3 world_pos;

varying float player_displacement_fake_perspective;

float location_seed (vec2 location) {
	return fract(sin(dot(location, vec2(12.9898,78.233))) * 43758.5453123);
}

float random(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

mat4 rotateAroundAxis(vec3 axis, float angle) {
	axis = normalize(axis);
	float c = cos(angle);
	float s = sin(angle);
	float oc = 1.0 - c;

	mat4 rotation = mat4(
		vec4(oc * axis.x * axis.x + c,
		oc * axis.x * axis.y - axis.z * s,
		oc * axis.z * axis.x + axis.y * s,
		0.0),

		vec4(oc * axis.x * axis.y + axis.z * s,
		oc * axis.y * axis.y + c,
		oc * axis.y * axis.z - axis.x * s,
		0.0),

		vec4(oc * axis.z * axis.x - axis.y * s,
		oc * axis.y * axis.z + axis.x * s,
		oc * axis.z * axis.z + c,
		0.0),

		vec4(0.0, 0.0, 0.0, 1.0)
	);
	return rotation;
}

mat4 view_space_rotate(float angle) {
	return mat4(
		vec4(cos(angle), -sin(angle), 0.0, 0.0),
		vec4(sin(angle), cos(angle), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void vertex() {
	instance_id = float(INSTANCE_ID);
	id_seed1 = random(instance_id);
	id_seed2 = random(instance_id + PI);
	object_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// Cluster-aware painterly density culling so non-meadow biomes reveal their painted floor patterns!
	if (blade_density < 0.995) {
		float cl_hash = fract(sin(dot(floor(object_origin.xz * 0.45), vec2(12.9898, 78.233))) * 43758.5453);
		float keep_score = mix(id_seed2, cl_hash, 0.62);
		if (keep_score > blade_density) {
			VERTEX = vec3(0.0);
		}
	}

	VERTEX *= blade_scale;

	if (id_seed1 < accent_frequency1) {
		VERTEX.y += accent_height1;
		VERTEX *= accent_scale1;
	}
	else if (id_seed2 < accent_probability2) {
		VERTEX.y += accent_height2;
		VERTEX *= accent_scale2;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float seed = 10.0 * location_seed(object_origin.xy);
	float frametime = 1.0 / framerate;
	float phase = mod(seed, frametime);

	float time = TIME;
	if (quantised) {
		time += phase;
		time = round(time * framerate) / framerate;
	}
	if (web_fast_mode) {
		float w_phase1 = dot(object_origin.xz, vec2(0.21, 0.34)) - time * 1.65;
		float w_phase2 = dot(object_origin.xz, vec2(-0.16, 0.27)) - time * 1.15;
		float w_wave = (sin(w_phase1) * 0.55 + cos(w_phase2) * 0.45) * 0.25 + 0.25;
		wind_noise_sample = (clamp(w_wave + wind_noise_threshold, 0.0, 1.0) - 0.5) * 2.0;
	} else {
		vec2 wind_noise_direction1 = rotate_vec2(wind_noise_direction, noise_diverge_angle);
		vec2 wind_noise_direction2 = rotate_vec2(wind_noise_direction, -noise_diverge_angle);
		vec2 wind_noise_time_direction1 = time * wind_noise_speed * normalize(wind_noise_direction1);
		vec2 wind_noise_time_direction2 = time * wind_noise_speed * normalize(wind_noise_direction2);
		float wind_noise_sample1 = texture(wind_noise, object_origin.xz * wind_noise_scale + wind_noise_time_direction1).r;
		float wind_noise_sample2 = texture(wind_noise, object_origin.xz * (wind_noise_scale * 0.8) + (wind_noise_time_direction2 * 0.89 * PI / 3.0)).r;
		wind_noise_sample = (wind_noise_sample1 * wind_noise_sample2);
		wind_noise_sample = clamp(wind_noise_sample + wind_noise_threshold, 0.0, 1.0);
		wind_noise_sample = (wind_noise_sample - 0.5) * 2.0;
	}

	float world_sway = wind_noise_sample * radians(world_sway_angle);
	vec3 wind_world_axis = (vec4(wind_noise_direction.y, 0.0, -wind_noise_direction.x, 1.0) * INV_VIEW_MATRIX).xyz;
	mat4 world_rotation = rotateAroundAxis(wind_world_axis, world_sway);

	float model_sway = sin((time + seed) * view_sway_speed * 2.0 * PI) * radians(view_sway_angle);
	mat4 model_rotation = view_space_rotate(model_sway);

	float character_displacement_x = 0.0;
	float character_displacement_y = 0.0;
	if (character_displacement && active_character_count > 0) {
		vec2 cam_fwd_xz = normalize(CAMERA_DIRECTION_WORLD.xz);
		vec2 cam_perp_xz = vec2(cam_fwd_xz.y, -cam_fwd_xz.x);
		for (int i = 0; i < character_count; i++) {
			if (i >= active_character_count) {
				break;
			}
			float r = character_positions[i].w;
			vec2 diff_xz = object_origin.xz - character_positions[i].xz;
			float d2 = dot(diff_xz, diff_xz);
			if (r > 0.001 && d2 < r * r && d2 > 0.000001) {
				float dist_norm = sqrt(d2) / r;
				float displacement_strength = pow(clamp(1.0 - dist_norm, 0.0, 1.0), radius_exponent);
				vec2 dir_xz = diff_xz * inversesqrt(d2);
				character_displacement_x += displacement_strength * dot(cam_perp_xz, dir_xz);
				character_displacement_y += displacement_strength * dot(cam_fwd_xz, dir_xz);
			}
		}
	}
	character_displacement_x = clamp(character_displacement_x, -1.0, 1.0);
	character_displacement_y = clamp(character_displacement_y, -1.0, 1.0);

	debug_interactive_color = vec3(
		character_displacement_x + character_displacement_y,
		-character_displacement_x + character_displacement_y,
		-character_displacement_y
	);

	mat4 player_displacement_rotation =
		rotateAroundAxis(vec3(0.0, 0.0, 1.0), character_displacement_x * radians(player_displacement_angle_z))
		* rotateAroundAxis(vec3(1.0, 0.0, 0.0), character_displacement_y * radians(player_displacement_angle_x));
	player_displacement_fake_perspective = character_displacement_y;

	if (view_space_sway) {
		VERTEX = (model_rotation * vec4(VERTEX, 1.0)).xyz;
	}
	if (character_displacement) {
		VERTEX = (player_displacement_rotation * vec4(VERTEX, 1.0)).xyz;
	}
	if (world_space_sway) {
		VERTEX = (world_rotation * vec4(VERTEX, 1.0)).xyz;
	}

	mat4 modified_model_view = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0),
		MODEL_MATRIX[3]
	);

	vec2 pool_diff_v = object_origin.xz - water_pool_center.xz;
	if (water_pool_radius > 0.0 && dot(pool_diff_v, pool_diff_v) < 12.25) {
		float pool_angle = atan(pool_diff_v.y, pool_diff_v.x);
		float pool_distort = sin(pool_angle * 2.0) * 0.45 + cos(pool_angle * 3.0 + 0.8) * 0.3 + sin(pool_angle * 5.0) * 0.15;
		float dynamic_bound = 2.45 + pool_distort;
		if (dot(pool_diff_v, pool_diff_v) < dynamic_bound * dynamic_bound) {
			VERTEX = vec3(0.0);
		}
	}

	model_origin = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	MODELVIEW_MATRIX = modified_model_view;
	debug_wind_color = wind_noise_sample;
}

void fragment() {
	vec2 uv = UV;
	uv.x -= 0.5;
	float _wind_noise_sample = (wind_noise_sample) * fake_perspective_scale;
	if (world_space_sway) {
		_wind_noise_sample *= dot(CAMERA_DIRECTION_WORLD.xz, wind_noise_direction);
		uv.x *= (1.0 - uv.y) * _wind_noise_sample + 1.0;
	}
	if (character_displacement) {
		uv.x *= (1.0 - uv.y) * -player_displacement_fake_perspective + 1.0;
	}
	uv.x += 0.5;
	uv.x = clamp(uv.x, 0.0, 1.0);

	vec4 albedo_tex = texture(albedo_texture, uv);
	float albedo2_noise_tex = texture(albedo2_noise, (object_origin.xz + noise_offset) * (albedo2_scale)).r;
	float albedo3_noise_tex = texture(albedo3_noise, (object_origin.xz + noise_offset) * (albedo3_scale)).r;
	ALBEDO = albedo1.rgb * albedo_tex.rgb;
	if (albedo2_noise_tex > albedo2_threshold) {
		ALBEDO = albedo2.rgb;
	}
	if (albedo3_noise_tex > albedo3_threshold) {
		ALBEDO = albedo3.rgb;
	}
	if (id_seed1 < accent_frequency1) {
		albedo_tex = texture(accent_texture1, uv);
		ALBEDO = accent_albedo1.rgb * albedo_tex.rgb;
	}
	else if (id_seed2 < accent_probability2) {
		albedo_tex = texture(accent_texture2, uv);
		ALBEDO = accent_albedo2.rgb * albedo_tex.rgb;
	}

	float tip_factor = pow(clamp(1.0 - uv.y, 0.0, 1.0), 1.6);
	if (anomaly_iridescence) {
		float ph = 0.5 + 0.5 * sin(object_origin.x * 0.14 + object_origin.z * 0.11 + TIME * 0.75 + id_seed1 * 3.14);
		vec3 iri = mix(vec3(0.14, 0.94, 1.0), vec3(1.0, 0.22, 0.68), ph);
		iri = mix(iri, vec3(1.0, 0.91, 0.52), step(0.84, id_seed2));
		ALBEDO = mix(ALBEDO, iri, tip_factor * 0.85);
		EMISSION = iri * tip_factor * tip_emission_strength;
	} else if (tip_emission_strength > 0.001) {
		ALBEDO = mix(ALBEDO, tip_emission_color.rgb, tip_factor * 0.52);
		EMISSION = tip_emission_color.rgb * tip_factor * tip_emission_strength;
	}

	LIGHT_VERTEX = model_origin;
	ALPHA = albedo_tex.a;
	vec2 pool_diff_f = object_origin.xz - water_pool_center.xz;
	if (water_pool_radius > 0.0 && dot(pool_diff_f, pool_diff_f) < 12.25) {
		float pool_angle = atan(pool_diff_f.y, pool_diff_f.x);
		float pool_distort = sin(pool_angle * 2.0) * 0.45 + cos(pool_angle * 3.0 + 0.8) * 0.3 + sin(pool_angle * 5.0) * 0.15;
		float dynamic_bound = 2.45 + pool_distort;
		if (dot(pool_diff_f, pool_diff_f) < dynamic_bound * dynamic_bound) {
			ALPHA = 0.0;
		}
	}
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (debug_noise) {
		ALBEDO = vec3(debug_wind_color);
	}
	if (debug_displacement) {
		ALBEDO = vec3(debug_interactive_color);
	}
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = NdotL + (ATTENUATION - 1.0) + wrap;
	diffuse_amount *= steepness;

	if (LIGHT_IS_DIRECTIONAL && !web_fast_mode) {
		vec3 vertex_world_pos = (INV_VIEW_MATRIX * vec4(model_origin, 1.0)).xyz;
		float light_value = get_cloud_noise(vertex_world_pos);
		diffuse_amount = min(diffuse_amount, light_value);
	}

	float cuts_inv = 1.0f / float(cuts);
	float cut = cuts_inv;
	float original_index = ceil(diffuse_amount * float(cuts));
	float original_stepped = clamp(original_index * cut, 0.0, 1.0);
	float diffuse_stepped = clamp(diffuse_amount + mod(1.0f - diffuse_amount, cuts_inv), 0.0f, 1.0f);

	if (threshold_gradient_size > 0.0) {
		float nearest_k = floor(diffuse_amount / cut + 0.5);
		float threshold = nearest_k * cut;

		if (nearest_k >= 0.0 && nearest_k <= float(cuts)) {
			float halfWidth = 0.5 * cut * threshold_gradient_size;
			float low  = max(0.0, threshold - halfWidth);
			float high = min(1.0, threshold + halfWidth);

			float blend = 0.0;
			if (high > low) {
				blend = smoothstep(low, high, diffuse_amount);
			} else {
				blend = step(threshold, diffuse_amount);
			}

			float leftValue  = threshold;
			float rightValue = min(threshold + (cut * 1.0), 0.0 + 1.0);
			diffuse_stepped = mix(leftValue, rightValue, blend);
			diffuse_stepped = clamp(diffuse_stepped, 0.0, 1.0);
		} else {
			diffuse_stepped = original_stepped;
		}
	}
	vec3 diffuse = ALBEDO.rgb * LIGHT_COLOR / PI;
	diffuse *= diffuse_stepped;
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
}
