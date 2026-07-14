shader_type canvas_item;

uniform vec4 baseColor : source_color = vec4(0.075, 0.086, 0.091, 1.0);
uniform vec4 lineColor : source_color = vec4(0.15, 0.17, 0.16, 0.42);
uniform float gridSize : hint_range(8.0, 256.0) = 32.0;
uniform float lineWidth : hint_range(0.1, 4.0) = 1.0;

void fragment() {
	vec2 viewportSize = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cell = abs(fract(UV * viewportSize / max(gridSize, 1.0)) - 0.5);
	float distanceToLine = 0.5 - max(cell.x, cell.y);
	float antiAlias = max(fwidth(distanceToLine), 0.0001);
	float gridLine = 1.0 - smoothstep(
		lineWidth / gridSize - antiAlias,
		lineWidth / gridSize + antiAlias,
		distanceToLine
	);
	COLOR = vec4(mix(baseColor.rgb, lineColor.rgb, gridLine * lineColor.a), baseColor.a);
}
