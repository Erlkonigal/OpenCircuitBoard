shader_type canvas_item;
render_mode blend_premul_alpha;

uniform vec4 topColor : source_color = vec4(1.0);
uniform vec4 sideShadowColor : source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform vec4 topUvBounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform float extrusionDepth : hint_range(0.0, 100.0) = 32.0;
uniform vec2 extrusionDirection = vec2(-0.707, 0.707);
uniform vec4 shadowColor : source_color = vec4(0.012, 0.022, 0.038, 0.42);
uniform float shadowProjectionDistance : hint_range(0.0, 300.0) = 20.0;
uniform float shadowDensity : hint_range(0.0, 1.0) = 0.48;
uniform float shadowFadePower : hint_range(0.1, 5.0) = 1.7;
uniform float shadowEdgeBlur : hint_range(0.0, 12.0) = 8.0;
uniform float renderShadowOnly : hint_range(0.0, 1.0) = 0.0;

const float seamOverlap = 0.5;
const float minimumFeather = 0.00001;

float topSignedDistance(vec2 uv) {
	vec2 lowerDistance = uv - topUvBounds.xy;
	vec2 upperDistance = topUvBounds.zw - uv;
	return min(min(lowerDistance.x, lowerDistance.y), min(upperDistance.x, upperDistance.y));
}

float coverageFromDistance(float signedDistance, float blurScale, float overlap) {
	float feather = max(fwidth(signedDistance) * blurScale, minimumFeather);
	return smoothstep(-feather, feather, signedDistance + feather * overlap);
}

float topCoverage(vec2 uv, float blurScale, float overlap) {
	return coverageFromDistance(topSignedDistance(uv), blurScale, overlap);
}

vec2 extrusionHit(vec2 uv, vec2 pixelSize, float depth) {
	vec2 rayDirection = -extrusionDirection * pixelSize;
	vec2 firstIntersections = (topUvBounds.xy - uv) / rayDirection;
	vec2 lastIntersections = (topUvBounds.zw - uv) / rayDirection;
	vec2 enterIntersections = min(firstIntersections, lastIntersections);
	vec2 exitIntersections = max(firstIntersections, lastIntersections);
	float enterDistance = max(0.0, max(enterIntersections.x, enterIntersections.y));
	float exitDistance = min(depth, min(exitIntersections.x, exitIntersections.y));
	return vec2(enterDistance, exitDistance);
}

float extrusionCoverage(vec2 uv, vec2 pixelSize, float depth, float blurScale, float overlap) {
	vec2 hit = extrusionHit(uv, pixelSize, depth);
	float hitLength = hit.y - hit.x;
	return coverageFromDistance(hitLength, blurScale, overlap);
}

float sideShadowMask(vec2 uv, vec2 pixelSize, float depth) {
	vec2 hit = extrusionHit(uv, pixelSize, depth);
	float sweepMask = coverageFromDistance(hit.y - hit.x, 1.0, 0.0);
	float topMask = coverageFromDistance(topSignedDistance(uv), 1.0, 0.0);
	float sideMask = max(sweepMask - topMask, 0.0);
	float projectionProgress = clamp(hit.x / depth, 0.0, 1.0);
	float projectionFade = 1.0 - 0.45 * pow(projectionProgress, shadowFadePower);
	return sideMask * projectionFade;
}

float sideShadowCoverage(vec2 uv, vec2 pixelSize, float depth) {
	vec2 direction = normalize(extrusionDirection);
	vec2 perpendicular = vec2(-direction.y, direction.x);
	float blurRadius = shadowEdgeBlur * 0.6;
	float shadowMask = sideShadowMask(uv, pixelSize, depth) * 0.4;
	shadowMask += sideShadowMask(uv + direction * blurRadius * pixelSize, pixelSize, depth) * 0.15;
	shadowMask += sideShadowMask(uv - direction * blurRadius * pixelSize, pixelSize, depth) * 0.15;
	shadowMask += sideShadowMask(uv + perpendicular * blurRadius * pixelSize, pixelSize, depth) * 0.15;
	shadowMask += sideShadowMask(uv - perpendicular * blurRadius * pixelSize, pixelSize, depth) * 0.15;
	return shadowMask;
}

void fragment() {
	vec2 pixelSize = TEXTURE_PIXEL_SIZE;
	float depth = max(extrusionDepth, 0.001);

	if (renderShadowOnly > 0.5) {
		vec2 shadowShift = extrusionDirection * shadowProjectionDistance * pixelSize;
		float shadowMask = sideShadowCoverage(UV - shadowShift, pixelSize, depth);
		float shadowAlpha = shadowColor.a * shadowDensity * shadowMask * COLOR.a;
		COLOR = vec4(shadowColor.rgb * shadowAlpha, shadowAlpha);
	} else {
		float topMask = topCoverage(UV, 1.0, seamOverlap);
		vec2 hit = extrusionHit(UV, pixelSize, depth);
		float extrusionMask = extrusionCoverage(UV, pixelSize, depth, 1.0, seamOverlap);
		float sideMask = max(extrusionMask - topMask, 0.0);
		float alphaScale = COLOR.a;
		float topAlpha = topMask * alphaScale;
		float sideAlpha = sideMask * alphaScale;
		float layerProgress = clamp(hit.x / depth, 0.0, 1.0);
		vec3 sideColor = mix(sideShadowColor.rgb + vec3(0.15), sideShadowColor.rgb, layerProgress);
		vec3 color = topColor.rgb * COLOR.rgb * topAlpha;
		color += sideColor * COLOR.rgb * sideAlpha;
		COLOR = vec4(color, clamp(topAlpha + sideAlpha, 0.0, 1.0));
	}
}
