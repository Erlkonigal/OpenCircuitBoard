shader_type canvas_item;
render_mode blend_premul_alpha;

uniform vec4 topColor : source_color = vec4(1.0);
uniform vec4 sideShadowColor : source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform float extrusionDepth : hint_range(0.0, 100.0) = 32.0;
uniform vec2 extrusionDirection = vec2(-0.707, 0.707);

void fragment() {
	vec2 pixelSize = TEXTURE_PIXEL_SIZE;
	vec4 surface = texture(TEXTURE, UV);
	vec4 result = vec4(topColor.rgb * surface.a, surface.a);
	for (float distance = 1.0; distance <= extrusionDepth; distance += 1.0) {
		float alpha = texture(TEXTURE, UV - extrusionDirection * distance * pixelSize).a;
		if (result.a < 0.99 && alpha > 0.0) {
			result.rgb = mix(sideShadowColor.rgb * alpha, result.rgb, result.a);
			result.a = max(result.a, alpha);
		}
	}
	COLOR = result;
}
