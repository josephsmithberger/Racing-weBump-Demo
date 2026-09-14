shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 paint_color : source_color = vec4(1.0, 0.2, 0.4, 1.0);
uniform bool use_paint_override = true;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float metallic : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	
	if (use_paint_override) {
		float max_c = max(tex.r, max(tex.g, tex.b));
		float min_c = min(tex.r, min(tex.g, tex.b));
		float sat = (max_c - min_c) / (max_c + 0.0001);
		
		// Trim, bumpers, windshields, and headlights have low saturation or low value
		if (sat < 0.15 || max_c < 0.35) {
			ALBEDO = tex.rgb;
		} else {
			ALBEDO = paint_color.rgb;
		}
	} else {
		ALBEDO = tex.rgb;
	}
	
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
