shader_type canvas_item;
render_mode blend_premul_alpha;

uniform vec4 topColor : source_color = vec4(1.0);
uniform vec4 sideShadowColor : source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform float extrusionDepth : hint_range(0.0, 100.0) = 32.0;
uniform vec2 extrusionDirection = vec2(-0.707, 0.707);
uniform vec4 shadowColor : source_color = vec4(0.0, 0.0, 0.0, 0.4);
uniform float shadowProjectionDistance : hint_range(0.0, 300.0) = 20.0;
uniform float shadowDensity : hint_range(0.0, 1.0) = 0.5;
uniform float shadowFadePower : hint_range(0.1, 5.0) = 2.0;
uniform float shadowEdgeBlur : hint_range(0.0, 5.0) = 2.5;
uniform float stepDensity : hint_range(0.1, 1.0) = 0.25;

void fragment() {
	vec2 pixelSize = TEXTURE_PIXEL_SIZE;
	float depth = max(extrusionDepth, 0.001);
	vec4 surface = texture(TEXTURE, UV);
	vec4 result = vec4(topColor.rgb * surface.a * COLOR.rgb, surface.a * COLOR.a);
	float opacityMask = result.a;

	if (opacityMask < 0.99) {
		for (float distance = stepDensity; distance <= depth; distance += stepDensity) {
			float sourceAlpha = texture(TEXTURE, UV - extrusionDirection * distance * pixelSize).a;
			if (sourceAlpha > 0.001) {
				float layerProgress = distance / depth;
				vec3 layerColor = mix(sideShadowColor.rgb + vec3(0.15), sideShadowColor.rgb, layerProgress);
				float contribution = sourceAlpha * (1.0 - opacityMask);
				result.rgb += layerColor * contribution;
				result.a += contribution;
				opacityMask += contribution;
				if (opacityMask > 0.99) {
					opacityMask = 1.0;
					break;
				}
			}
		}
	}

	if (opacityMask < 0.99) {
		vec2 shadowShift = extrusionDirection * shadowProjectionDistance * pixelSize;
		float shadowAmount = 0.0;
		for (float distance = 0.0; distance <= depth; distance += 2.0) {
			vec2 sliceOffset = extrusionDirection * distance * pixelSize;
			float blockerAlpha = textureLod(TEXTURE, UV - sliceOffset - shadowShift, shadowEdgeBlur).a;
			if (blockerAlpha > 0.0) {
				float distanceRatio = distance / depth;
				float fade = pow(1.0 - distanceRatio, shadowFadePower);
				shadowAmount = max(shadowAmount, shadowColor.a * blockerAlpha * fade * shadowDensity);
				if (shadowAmount > 0.98) break;
			}
		}
		result.rgb += shadowColor.rgb * shadowAmount * (1.0 - opacityMask);
		result.a += shadowAmount * (1.0 - opacityMask);
	}
	COLOR = vec4(result.rgb, clamp(result.a, 0.0, 1.0));
}
