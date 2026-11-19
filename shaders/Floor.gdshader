// MIT License.
// Made by Dylearn — Extended with Calm, High-Contrast Painterly Biome Floors (Shape of Dreams x Arcane)

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
uniform bool enable_cloud_shadows = true;

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
uniform vec3 player_focus_pos = vec3(0.0);
uniform vec4 player_wake[4];

varying vec3 vertex_pos;
varying vec3 normal;
varying vec3 vertex_world;

#include "res://shaders/clouds.gdshaderinc"

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}

float val_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453123);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453123);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453123);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453123);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm4(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		v += amp * val_noise(p);
		p = rot * p * 2.04 + vec2(11.7, 5.3);
		amp *= 0.5;
	}
	return v;
}

vec2 eval_pinpoint_stars(vec2 p, float scale_f, float thresh, float dot_r, float t_now) {
	vec2 uv = p * scale_f;
	vec2 id = floor(uv);
	vec2 f = fract(uv);
	vec2 rnd = hash22(id + vec2(5.1, 19.3));
	float pick = fract(sin(dot(id, vec2(91.7, 213.9))) * 43758.5453);
	if (pick < thresh) {
		return vec2(0.0);
	}
	vec2 sp = vec2(0.18) + 0.64 * rnd;
	float ds = length(f - sp);
	float tw = 0.68 + 0.32 * sin(t_now * (2.2 + 2.4 * rnd.x) + pick * 28.0);
	float core = (1.0 - smoothstep(dot_r * 0.35, dot_r, ds)) * tw;
	return vec2(core, rnd.y);
}

vec3 voronoi_glacier(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float md1 = 8.0;
	float md2 = 8.0;
	float cid = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + (0.14 + 0.72 * o) - f;
			float d = dot(r, r);
			if (d < md1) {
				md2 = md1;
				md1 = d;
				cid = o.x;
			} else if (d < md2) {
				md2 = d;
			}
		}
	}
	float s1 = sqrt(md1);
	float s2 = sqrt(md2);
	return vec3(s1, s2 - s1, cid);
}

vec2 seg_dist_param(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(0.0001, dot(ba, ba)), 0.0, 1.0);
	return vec2(length(pa - ba * h), h);
}

vec2 astral_star_pos(vec2 c) {
	return c + vec2(0.22) + 0.56 * hash22(c);
}

float eval_constellation_edge(vec2 uv_p, vec2 c_a, vec2 c_b, float seed_tag, float t_now) {
	vec2 h_rnd = hash22(c_a * 1.37 + c_b * 2.91 + vec2(seed_tag));
	vec2 a = astral_star_pos(c_a);
	vec2 b = astral_star_pos(c_b);
	vec2 dp = seg_dist_param(uv_p, a, b);
	float width_mask = 1.0 - smoothstep(0.003, 0.012, dp.x);
	if (width_mask <= 0.0001) {
		return 0.0;
	}
	float speed = 0.55 + 0.40 * h_rnd.y;
	float cycle = sin(t_now * speed + h_rnd.x * 6.2831853);
	float fade = smoothstep(-0.25, 0.62, cycle);
	float flow = 0.68 + 0.32 * sin(dp.y * 3.1415926 - t_now * 1.7 + h_rnd.x * 6.2831853);
	return width_mask * fade * flow;
}

float eval_shooting_star(vec2 world_xz, float angle_deg, float seed_off, float t_now) {
	vec2 m_pos = rotate_vec2(world_xz, angle_deg);
	vec2 patch_size = vec2(20.0, 8.5);
	vec2 patch_id = floor(m_pos / patch_size);
	vec2 local_p = m_pos - patch_id * patch_size;

	vec2 h_base = hash22(patch_id + vec2(seed_off, seed_off * 1.7));
	float rate = 0.12 + 0.06 * h_base.y;
	float cycle_t = t_now * rate + h_base.x * 9.0;
	float epoch = floor(cycle_t);
	float u = fract(cycle_t);

	float active_span = 0.36;
	if (u >= active_span) {
		return 0.0;
	}
	vec2 h_ep = hash22(patch_id + vec2(epoch * 3.13 + seed_off, epoch * 7.19));
	if (h_ep.x < 0.52) {
		return 0.0;
	}

	float prog = u / active_span;
	float env = sin(prog * PI);
	float y_lane = 2.2 + 4.1 * h_ep.y;
	float head_x = mix(3.8, 16.8, prog);

	float dx = head_x - local_p.x;
	float dy = abs(local_p.y - y_lane);
	float tail_len = 2.6;

	float streak = 0.0;
	if (dx >= 0.0 && dx <= tail_len) {
		float t_tail = 1.0 - (dx / tail_len);
		float half_w = mix(0.012, 0.042, t_tail);
		float w_mask = 1.0 - smoothstep(half_w * 0.2, half_w, dy);
		streak = w_mask * pow(t_tail, 1.8);
	}
	float d_head = length(vec2(local_p.x - head_x, local_p.y - y_lane));
	float head_glow = 1.0 - smoothstep(0.02, 0.11, d_head);

	return max(streak * 0.65, head_glow * 0.85) * env;
}

void vertex() {
	vertex_pos = VERTEX;
	normal = NORMAL;
	vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n2 = texture(albedo2_noise, (vertex_world.xz + noise_offset) * albedo2_scale).r;
	float n3 = texture(albedo3_noise, (vertex_world.xz + noise_offset) * albedo3_scale).r;

	ALBEDO = albedo1.rgb;
	if (n2 > albedo2_threshold) {
		ALBEDO = albedo2.rgb;
	}
	if (n3 > albedo3_threshold) {
		ALBEDO = albedo3.rgb;
	}

	vec3 emissive = vec3(0.0);

	if (biome_fx_mode == 1) {
		// Glacial Frostfield: faceted Voronoi glacier ice-sheet plates + deep cerulean crevasses + crystal cracks
		vec3 v1 = voronoi_glacier(vertex_world.xz * 0.14);
		vec3 v2 = voronoi_glacier(vertex_world.xz * 0.33 + vec2(17.3, 9.1));
		float slab_tone = mix(0.88, 1.12, v1.z);
		ALBEDO *= slab_tone;
		float deep_crevasse = 1.0 - smoothstep(0.025, 0.145, v1.y);
		float sub_fissure = (1.0 - smoothstep(0.015, 0.085, v2.y)) * 0.45;
		ALBEDO = mix(ALBEDO, fx_color2.rgb, clamp(deep_crevasse * 0.62 + sub_fissure * 0.35, 0.0, 0.78));
		float ice_crack = max(1.0 - smoothstep(0.004, 0.026, v1.y), (1.0 - smoothstep(0.003, 0.018, v2.y)) * 0.65);
		ALBEDO = mix(ALBEDO, fx_color1.rgb, ice_crack * 0.82);
		float glint = smoothstep(0.92, 0.99, sin(vertex_world.x * 3.7 + v1.z * 19.0) * cos(vertex_world.z * 3.5 - v2.z * 15.0));
		ALBEDO = mix(ALBEDO, fx_color3.rgb, glint * 0.35);
		emissive = (fx_color1.rgb * ice_crack * 0.65 + fx_color2.rgb * deep_crevasse * 0.55 + fx_color3.rgb * glint * 0.40) * fx_emission_strength;
	} else if (biome_fx_mode == 2) {
		// Astral Constellation: calm deep midnight-indigo starry cosmos, crisp pinpoint parallax stars & player-wake constellations
		float d_player = length(vertex_world.xz - player_focus_pos.xz);
		float wake_factor = 1.0 - smoothstep(2.6, 8.8, d_player);
		for (int w = 0; w < 4; w++) {
			vec4 wk = player_wake[w];
			float w_strength = clamp(wk.w, 0.0, 1.0);
			if (w_strength > 0.005) {
				float dw = length(vertex_world.xz - wk.xz);
				wake_factor = max(wake_factor, (1.0 - smoothstep(1.8, 6.2, dw)) * w_strength);
			}
		}

		float depth_shift = fbm4(vertex_world.xz * 0.032 + vec2(TIME * 0.008, -TIME * 0.006));
		float banded_depth = mix(depth_shift, floor(depth_shift * 4.0) / 4.0, 0.30);
		vec3 space_base = ALBEDO * mix(0.86, 1.14, banded_depth);

		// Crisp multi-depth pinpoint parallax starfield
		vec2 cam_xz = INV_VIEW_MATRIX[3].xz;
		vec2 p_mid = vertex_world.xz + (vertex_world.xz - cam_xz) * 0.06;
		vec2 p_deep = vertex_world.xz + (vertex_world.xz - cam_xz) * 0.12;
		vec2 st_deep = eval_pinpoint_stars(p_deep, 2.35, 0.74, 0.072, TIME);
		vec2 st_mid = eval_pinpoint_stars(p_mid + vec2(23.1, 7.4), 1.10, 0.80, 0.038, TIME * 0.85);
		vec3 ivory = vec3(0.96, 0.97, 1.0);
		vec3 st_deep_col = mix(ivory, fx_color3.rgb, step(0.65, st_deep.y));
		vec3 st_mid_col = mix(mix(ivory, fx_color1.rgb, 0.38), fx_color3.rgb, step(0.58, st_mid.y));

		// Needle-sharp 4-point hero constellation stars + subtle player-wake halos & connecting threads
		vec2 uv_star = vertex_world.xz * 0.24;
		vec2 cell = floor(uv_star);
		vec2 star_p = astral_star_pos(cell);
		vec2 dv = uv_star - star_p;
		float d_star = length(dv);
		float twinkle = 0.78 + 0.22 * sin(TIME * 2.2 + cell.x * 3.1 + cell.y * 5.7);
		float sp_h = (1.0 - smoothstep(0.001, 0.004, abs(dv.y))) * (1.0 - smoothstep(0.0, 0.038, abs(dv.x)));
		float sp_v = (1.0 - smoothstep(0.001, 0.004, abs(dv.x))) * (1.0 - smoothstep(0.0, 0.038, abs(dv.y)));
		float flare = max(sp_h, sp_v);
		float star_core = max(1.0 - smoothstep(0.003, 0.011, d_star), flare * 0.88) * twinkle * mix(0.80, 1.38, wake_factor);
		float star_halo = (1.0 - smoothstep(0.036, 0.056, d_star)) * smoothstep(0.020, 0.034, d_star) * wake_factor * (0.75 + 0.25 * sin(TIME * 4.2));

		float line_mask = 0.0;
		for (int dx = 0; dx <= 1; dx++) {
			vec2 ca_h = cell - vec2(float(dx), 0.0);
			if (hash22(ca_h + vec2(7.3, 2.9)).x > 0.46) {
				line_mask = max(line_mask, eval_constellation_edge(uv_star, ca_h, ca_h + vec2(1.0, 0.0), 1.1, TIME));
			}
		}
		for (int dy = 0; dy <= 1; dy++) {
			vec2 ca_v = cell - vec2(0.0, float(dy));
			if (hash22(ca_v + vec2(7.3, 2.9)).y > 0.48) {
				line_mask = max(line_mask, eval_constellation_edge(uv_star, ca_v, ca_v + vec2(0.0, 1.0), 3.7, TIME));
			}
		}
		float line_vis = line_mask * mix(0.07, 0.95, wake_factor);

		float meteor = max(
			eval_shooting_star(vertex_world.xz, -32.0, 11.3, TIME),
			eval_shooting_star(vertex_world.xz, -18.0, 47.9, TIME)
		);

		float h_pick = hash22(cell + vec2(7.3, 2.9)).x;
		vec3 star_col = mix(fx_color1.rgb, fx_color3.rgb, step(0.55, h_pick));
		vec3 meteor_col = mix(fx_color1.rgb, fx_color3.rgb, 0.45);

		ALBEDO = space_base;
		ALBEDO = mix(ALBEDO, st_deep_col, clamp(st_deep.x * 0.65, 0.0, 1.0));
		ALBEDO = mix(ALBEDO, st_mid_col, clamp(st_mid.x * 0.80, 0.0, 1.0));
		ALBEDO = mix(ALBEDO, star_col, clamp(line_vis * 0.50 + star_core * 0.90 + star_halo * 0.55, 0.0, 1.0));
		ALBEDO = mix(ALBEDO, meteor_col, clamp(meteor * 0.22, 0.0, 1.0));

		vec3 star_emit = st_deep_col * st_deep.x * 0.55 + st_mid_col * st_mid.x * 0.72 + star_col * (star_core * 0.92 + star_halo * 0.78) + fx_color1.rgb * line_vis * 0.52 + meteor_col * meteor * 0.26;
		emissive = star_emit * fx_emission_strength;
	} else if (biome_fx_mode == 3) {
		// Volcanic Caldera: wide matte basalt stone slabs with restrained warm ember seams (keeps combat floor clean & dark!)
		float seam = 1.0 - smoothstep(0.002, 0.014, abs(n2 - 0.54));
		float pulse = 0.85 + 0.15 * sin(TIME * 1.6 + vertex_world.x * 0.22 + vertex_world.z * 0.18);
		vec3 ember_col = mix(fx_color2.rgb, fx_color1.rgb, seam * 0.45);
		ALBEDO = mix(ALBEDO, ember_col, seam * 0.42);
		emissive = ember_col * seam * pulse * fx_emission_strength;
	} else if (biome_fx_mode == 4) {
		// Arcane Anomaly: moody painterly watercolour washes (deep plum / muted teal) with subtle soft iridescent shimmer
		float swirl = sin(n2 * 7.5 + n3 * 5.5 + TIME * 0.32);
		float cel_band = floor((swirl * 0.5 + 0.5) * 3.0) / 3.0;
		vec3 wash_tint = mix(fx_color1.rgb, fx_color2.rgb, cel_band);
		ALBEDO = mix(ALBEDO, ALBEDO * 0.82 + wash_tint * 0.16, 0.48);

		float fine_vein = 1.0 - smoothstep(0.001, 0.009, abs(n2 - 0.53));
		vec3 vein_col = mix(fx_color1.rgb, fx_color3.rgb, 0.5 + 0.5 * sin(vertex_world.x * 0.12 - vertex_world.z * 0.10 + TIME * 0.5));
		ALBEDO = mix(ALBEDO, vein_col, fine_vein * 0.28);
		emissive = (vein_col * fine_vein * 0.35 + wash_tint * 0.05) * fx_emission_strength;
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

	if (LIGHT_IS_DIRECTIONAL && enable_cloud_shadows) {
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
