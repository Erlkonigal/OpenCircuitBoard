shader_type canvas_item;

uniform vec4 baseColor : source_color = vec4(0.08, 0.11, 0.16, 1.0);
uniform float shade0 : hint_range(0.0, 2.0) = 1.0;
uniform float shade1 : hint_range(0.0, 2.0) = 0.97;
uniform float shade2 : hint_range(0.0, 2.0) = 0.94;
uniform float shade3 : hint_range(0.0, 2.0) = 0.91;
uniform float shade4 : hint_range(0.0, 2.0) = 0.94;
uniform float shade5 : hint_range(0.0, 2.0) = 0.97;
uniform float patternSize : hint_range(64.0, 4096.0) = 1024.0;
uniform vec2 boardSize = vec2(2560.0, 1792.0);

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

void fragment() {
	vec2 patternPosition = (UV * boardSize) / max(patternSize * 0.5, 1.0);
	vec2 localPosition = getHexPosition(patternPosition);
	float angle = atan(localPosition.y, localPosition.x) + PI / 6.0;
	int sector = int(floor(fract(angle / (2.0 * PI)) * 6.0));
	float brightness = shade0;
	if (sector == 1) brightness = shade1;
	else if (sector == 2) brightness = shade2;
	else if (sector == 3) brightness = shade3;
	else if (sector == 4) brightness = shade4;
	else if (sector == 5) brightness = shade5;
	COLOR = vec4(applyShade(baseColor.rgb, brightness), baseColor.a);
}
