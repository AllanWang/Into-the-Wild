shader_type canvas_item;

uniform vec4 color1 : source_color = vec4(0.24, 0.27, 0.32, 1.0);
uniform vec4 color2 : source_color = vec4(0.18, 0.20, 0.24, 1.0);
uniform float cell_size : hint_range(16.0, 256.0, 8.0) = 64.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 check = floor(world_pos / cell_size);
	float c = mod(check.x + check.y, 2.0);
	COLOR = mix(color1, color2, c);
}
