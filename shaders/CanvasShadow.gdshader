shader_type canvas_item;

uniform vec2 BoardSize = vec2(2560.0, 1792.0);
uniform vec2 FrameSize = vec2(3072.0, 2304.0);
uniform vec2 BoardOffset = vec2(256.0, 256.0);
uniform float CornerRadius : hint_range(0.0, 512.0) = 64.0;
uniform float ShadowBlur : hint_range(1.0, 256.0) = 192.0;
uniform vec4 ShadowColor : source_color = vec4(0.005, 0.009, 0.017, 0.28);

float roundedRectangleDistance(vec2 position, vec2 rectanglePosition, vec2 rectangleSize, float radius) {
	float clampedRadius = min(radius, min(rectangleSize.x, rectangleSize.y) * 0.5);
	vec2 rectangleCenter = rectanglePosition + rectangleSize * 0.5;
	vec2 halfSize = rectangleSize * 0.5;
	vec2 cornerDistance = abs(position - rectangleCenter) - halfSize + vec2(clampedRadius);
	return length(max(cornerDistance, vec2(0.0))) + min(max(cornerDistance.x, cornerDistance.y), 0.0) - clampedRadius;
}

void fragment() {
	vec2 position = UV * FrameSize;
	float distance = roundedRectangleDistance(
		position,
		BoardOffset,
		BoardSize,
		CornerRadius
	);
	float shadow = 1.0 - smoothstep(0.0, ShadowBlur, distance);
	COLOR = vec4(ShadowColor.rgb, ShadowColor.a * shadow);
}
