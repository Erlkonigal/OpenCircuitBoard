shader_type canvas_item;

uniform vec4 baseColor : source_color = vec4(0.13, 0.15, 0.18, 1.0);
uniform vec4 gridColor : source_color = vec4(0.28, 0.34, 0.39, 0.55);
uniform float cellSize = 64.0;
uniform vec2 boardSize = vec2(2560.0, 1792.0);

void fragment() {
	vec2 boardPosition = UV * boardSize;
	vec2 cellPosition = abs(fract(boardPosition / cellSize) - 0.5);
	float line = step(0.485, max(cellPosition.x, cellPosition.y));
	COLOR = mix(baseColor, gridColor, line);
}
