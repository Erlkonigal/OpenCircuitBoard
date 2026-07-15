shader_type canvas_item;

uniform vec4 BaseColor : source_color = vec4(0.08, 0.11, 0.16, 1.0);
uniform float Shade0 : hint_range(0.0, 2.0) = 1.0;
uniform float Shade1 : hint_range(0.0, 2.0) = 0.97;
uniform float Shade2 : hint_range(0.0, 2.0) = 0.94;
uniform float Shade3 : hint_range(0.0, 2.0) = 0.91;
uniform float Shade4 : hint_range(0.0, 2.0) = 0.94;
uniform float Shade5 : hint_range(0.0, 2.0) = 0.97;
uniform float PatternSize : hint_range(64.0, 4096.0) = 1024.0;
uniform vec2 BoardSize = vec2(2560.0, 1792.0);
uniform vec2 PatternOrigin = vec2(0.0);
uniform float CornerRadius : hint_range(0.0, 512.0) = 64.0;
uniform float EdgeSoftness : hint_range(0.1, 8.0) = 1.0;

const float sqrt3 = 1.7320508;

vec2 getHexPosition(vec2 patternPosition) {
	vec2 repeatSize = vec2(1.0, sqrt3);
	vec2 halfSize = repeatSize * 0.5;
	vec2 firstCell = mod(patternPosition, repeatSize) - halfSize;
	vec2 secondCell = mod(patternPosition - halfSize, repeatSize) - halfSize;
	if (dot(firstCell, firstCell) < dot(secondCell, secondCell)) {
		return firstCell;
	}
	return secondCell;
}

vec3 applyShade(vec3 color, float brightness) {
	if (brightness <= 1.0) {
		return color * brightness;
	}
	return mix(color, vec3(1.0), brightness - 1.0);
}

float roundedRectangleDistance(vec2 position, vec2 size, float radius) {
	float clampedRadius = min(radius, min(size.x, size.y) * 0.5);
	vec2 halfSize = size * 0.5;
	vec2 cornerDistance = abs(position - halfSize) - halfSize + vec2(clampedRadius);
	return length(max(cornerDistance, vec2(0.0))) + min(max(cornerDistance.x, cornerDistance.y), 0.0) - clampedRadius;
}

void fragment() {
	vec2 boardPosition = UV * BoardSize;
	vec2 patternPosition = (boardPosition + PatternOrigin) / max(PatternSize * 0.5, 1.0);
	vec2 localPosition = getHexPosition(patternPosition);
	float angle = atan(localPosition.y, localPosition.x) + PI / 6.0;
	int sector = int(floor(fract(angle / (2.0 * PI)) * 6.0));
	float brightness = Shade0;
	if (sector == 1) brightness = Shade1;
	else if (sector == 2) brightness = Shade2;
	else if (sector == 3) brightness = Shade3;
	else if (sector == 4) brightness = Shade4;
	else if (sector == 5) brightness = Shade5;
	float edgeDistance = roundedRectangleDistance(boardPosition, BoardSize, CornerRadius);
	float boardMask = 1.0 - smoothstep(-EdgeSoftness, EdgeSoftness, edgeDistance);
	vec3 boardColor = applyShade(BaseColor.rgb, brightness);
	COLOR = vec4(boardColor, BaseColor.a * boardMask);
}
