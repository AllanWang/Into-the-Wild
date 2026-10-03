shader_type canvas_item;

global uniform vec2 player_position;

uniform float wind_speed = 2.0;
uniform float wind_strength = 10.0;
uniform float wind_scale = 0.02;

uniform float player_bend_radius = 80.0;
uniform float player_bend_strength = 45.0;

// Glow uniforms
uniform float glow_radius = 200.0;
uniform float glow_strength = 0.8;
uniform vec4 glow_color : source_color = vec4(0.3, 0.7, 1.0, 1.0); // Cyan-blue glow

uniform vec4 base_color : source_color = vec4(0.08, 0.33, 0.17, 1.0); // Dark grass
uniform vec4 tip_color : source_color = vec4(0.15, 0.65, 0.3, 1.0);   // Light green
uniform vec4 accent_color : source_color = vec4(0.35, 0.8, 0.45, 1.0); // Highlight green

varying vec2 v_world_pos;

void vertex() {
	float influence = 1.0 - UV.y; // Apply only to the top parts
	
	// World position of the vertex
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	
	// Wind sway using TIME
	float wind_offset = sin(TIME * wind_speed + v_world_pos.x * wind_scale) * wind_strength;
	VERTEX.x += wind_offset * influence;
	
	// Player bending reaction
	vec2 player_to_vertex = v_world_pos - player_position;
	float dist_to_player = length(player_to_vertex);
	
	if (dist_to_player < player_bend_radius) {
		// Linear falloff of force based on distance
		float force = (1.0 - (dist_to_player / player_bend_radius)) * player_bend_strength;
		
		// Vector pointing away from the player
		vec2 bend_dir = normalize(player_to_vertex);
		
		// Transform world direction to local space for displacement
		vec2 local_bend = (inverse(MODEL_MATRIX) * vec4(bend_dir, 0.0, 0.0)).xy;
		
		// Apply displacement
		VERTEX += local_bend * force * influence;
	}
}

void fragment() {
	float height = 1.0 - UV.y;
	
	// Stepped toon coloring based on vertical height
	vec4 col;
	if (height > 0.75) {
		col = accent_color;
	} else if (height > 0.35) {
		col = tip_color;
	} else {
		col = base_color;
	}
	
	// Modulate the pixel art texture with the height-based toon color
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Calculate glow overlay on the grass based on distance from player in world space
	float dist_to_player = length(v_world_pos - player_position);
	float glow_factor = 0.0;
	if (dist_to_player < glow_radius) {
		// Stronger glow near the player, with vertical fade (glows brighter at tips)
		glow_factor = (1.0 - (dist_to_player / glow_radius)) * (height * 0.5 + 0.5);
		glow_factor = smoothstep(0.0, 1.0, glow_factor);
	}
	
	vec3 final_rgb = tex_color.rgb * col.rgb;
	// Additive glow reflecting on the grass pixels
	final_rgb += glow_color.rgb * glow_factor * glow_strength;
	
	COLOR = vec4(final_rgb, tex_color.a * col.a);
}
