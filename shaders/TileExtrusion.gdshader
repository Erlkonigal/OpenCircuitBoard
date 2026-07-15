shader_type canvas_item;
render_mode blend_premul_alpha;

uniform vec4 TopColor : source_color = vec4(1.0);
uniform vec4 SideShadowColor : source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform vec4 TopUvBounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform float ExtrusionDepth : hint_range(0.0, 100.0) = 32.0;
uniform vec2 ExtrusionDirection = vec2(-0.707, 0.707);
uniform vec4 ShadowColor : source_color = vec4(0.012, 0.022, 0.038, 0.42);
uniform float ShadowProjectionDistance : hint_range(0.0, 300.0) = 20.0;
uniform float ShadowDensity : hint_range(0.0, 1.0) = 0.48;
uniform float ShadowFadePower : hint_range(0.1, 5.0) = 1.7;
uniform float ShadowEdgeBlur : hint_range(0.0, 12.0) = 8.0;
uniform float RenderShadowOnly : hint_range(0.0, 1.0) = 0.0;

const float seamOverlap = 0.4;
const float minimumFeather = 0.00001;

float topSignedDistance(vec2 uv) {
	vec2 center = (TopUvBounds.xy + TopUvBounds.zw) * 0.5;
	vec2 halfSize = (TopUvBounds.zw - TopUvBounds.xy) * 0.5;
	vec2 delta = abs(uv - center) - halfSize;
	float signedDistance = length(max(delta, vec2(0.0))) + min(max(delta.x, delta.y), 0.0);
	return -signedDistance;
}

float cross2(vec2 first, vec2 second) {
	return first.x * second.y - first.y * second.x;
}

float pointSegmentDistance(vec2 point, vec2 start, vec2 end) {
	vec2 edge = end - start;
	float edgeLengthSquared = max(dot(edge, edge), 0.000000000001);
	float edgeProgress = clamp(dot(point - start, edge) / edgeLengthSquared, 0.0, 1.0);
	return length(point - (start + edge * edgeProgress));
}

float extrusionSignedDistance(vec2 point, vec2 pixelSize, float depth) {
	vec2 topMin = TopUvBounds.xy;
	vec2 topMax = TopUvBounds.zw;
	vec2 extrusionOffset = ExtrusionDirection * depth * pixelSize;
	vec2 vertex0 = topMin;
	vec2 vertex1 = vec2(topMax.x, topMin.y);
	vec2 vertex2 = topMax;
	vec2 vertex3 = topMax + extrusionOffset;
	vec2 vertex4 = vec2(topMin.x, topMax.y) + extrusionOffset;
	vec2 vertex5 = topMin + extrusionOffset;
	float minCross = min(
		min(cross2(vertex1 - vertex0, point - vertex0), cross2(vertex2 - vertex1, point - vertex1)),
		min(
			min(cross2(vertex3 - vertex2, point - vertex2), cross2(vertex4 - vertex3, point - vertex3)),
			min(cross2(vertex5 - vertex4, point - vertex4), cross2(vertex0 - vertex5, point - vertex5))
		)
	);
	float edgeDistance = min(
		min(pointSegmentDistance(point, vertex0, vertex1), pointSegmentDistance(point, vertex1, vertex2)),
		min(
			min(pointSegmentDistance(point, vertex2, vertex3), pointSegmentDistance(point, vertex3, vertex4)),
			min(pointSegmentDistance(point, vertex4, vertex5), pointSegmentDistance(point, vertex5, vertex0))
		)
	);
	return edgeDistance * (minCross >= 0.0 ? 1.0 : -1.0);
}

float coverageFromDistance(float signedDistance, float blurScale, float overlap) {
	float feather = max(fwidth(signedDistance) * blurScale, minimumFeather);
	return smoothstep(-feather, feather, signedDistance + feather * overlap);
}

float topCoverage(vec2 uv, float blurScale, float overlap) {
	return coverageFromDistance(topSignedDistance(uv), blurScale, overlap);
}

vec2 extrusionHit(vec2 uv, vec2 pixelSize, float depth) {
	vec2 rayDirection = -ExtrusionDirection * pixelSize;
	vec2 firstIntersections = (TopUvBounds.xy - uv) / rayDirection;
	vec2 lastIntersections = (TopUvBounds.zw - uv) / rayDirection;
	vec2 enterIntersections = min(firstIntersections, lastIntersections);
	vec2 exitIntersections = max(firstIntersections, lastIntersections);
	float enterDistance = max(0.0, max(enterIntersections.x, enterIntersections.y));
	float exitDistance = min(depth, min(exitIntersections.x, exitIntersections.y));
	return vec2(enterDistance, exitDistance);
}

float extrusionCoverage(vec2 uv, vec2 pixelSize, float depth, float blurScale, float overlap) {
	return coverageFromDistance(extrusionSignedDistance(uv, pixelSize, depth), blurScale, overlap);
}

float sideShadowMask(vec2 uv, vec2 pixelSize, float depth) {
	vec2 hit = extrusionHit(uv, pixelSize, depth);
	float sweepMask = coverageFromDistance(hit.y - hit.x, 1.0, 0.0);
	float topMask = coverageFromDistance(topSignedDistance(uv), 1.0, 0.0);
	float sideMask = max(sweepMask - topMask, 0.0);
	float projectionProgress = clamp(hit.x / depth, 0.0, 1.0);
	float projectionFade = 1.0 - 0.45 * pow(projectionProgress, ShadowFadePower);
	return sideMask * projectionFade;
}

float sideShadowCoverage(vec2 uv, vec2 pixelSize, float depth) {
	vec2 direction = normalize(ExtrusionDirection);
	vec2 perpendicular = vec2(-direction.y, direction.x);
	float blurRadius = ShadowEdgeBlur * 0.6;
	float shadowMask = sideShadowMask(uv, pixelSize, depth) * 0.4;
	shadowMask += sideShadowMask(uv + direction * blurRadius * pixelSize, pixelSize, depth) * 0.15;
	shadowMask += sideShadowMask(uv - direction * blurRadius * pixelSize, pixelSize, depth) * 0.15;
	shadowMask += sideShadowMask(uv + perpendicular * blurRadius * pixelSize, pixelSize, depth) * 0.15;
	shadowMask += sideShadowMask(uv - perpendicular * blurRadius * pixelSize, pixelSize, depth) * 0.15;
	return shadowMask;
}

void fragment() {
	vec2 pixelSize = TEXTURE_PIXEL_SIZE;
	float depth = max(ExtrusionDepth, 0.001);

	if (RenderShadowOnly > 0.5) {
		vec2 shadowShift = ExtrusionDirection * ShadowProjectionDistance * pixelSize;
		float shadowMask = sideShadowCoverage(UV - shadowShift, pixelSize, depth);
		float shadowAlpha = ShadowColor.a * ShadowDensity * shadowMask * COLOR.a;
		COLOR = vec4(ShadowColor.rgb * shadowAlpha, shadowAlpha);
	} else {
		float topMask = topCoverage(UV, 1.0, seamOverlap);
		vec2 hit = extrusionHit(UV, pixelSize, depth);
		float extrusionMask = extrusionCoverage(UV, pixelSize, depth, 1.0, seamOverlap);
		float sideMask = max(extrusionMask - topMask, 0.0);
		float alphaScale = COLOR.a;
		float topAlpha = topMask * alphaScale;
		float sideAlpha = sideMask * alphaScale;
		float layerProgress = clamp(hit.x / depth, 0.0, 1.0);
		vec3 sideColor = mix(SideShadowColor.rgb + vec3(0.15), SideShadowColor.rgb, layerProgress);
		vec3 color = TopColor.rgb * COLOR.rgb * topAlpha;
		color += sideColor * COLOR.rgb * sideAlpha;
		COLOR = vec4(color, clamp(topAlpha + sideAlpha, 0.0, 1.0));
	}
}
