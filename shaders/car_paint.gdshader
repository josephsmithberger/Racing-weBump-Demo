shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 paint_color : source_color = vec4(1.0, 0.2, 0.4, 1.0);
uniform bool use_paint_override = true;
// 0 = orange/yellow, 1 = red/pink, 2 = green, 3 = blue
uniform int paint_mask = 0;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float metallic : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	
	if (use_paint_override) {
		// The model palette encodes paint and functional details in the same mesh.
		// Match only the palette range used by this vehicle's painted body panels.
		bool is_paint_region = false;
		if (paint_mask == 0) {
			is_paint_region = tex.r > tex.g * 1.6 && tex.g > tex.b * 1.5;
		} else if (paint_mask == 1) {
			is_paint_region = tex.r > tex.b * 1.5 && tex.b > tex.g * 1.4;
		} else if (paint_mask == 2) {
			is_paint_region = tex.g > tex.r * 1.5 && tex.g > tex.b * 1.5;
		} else if (paint_mask == 3) {
			is_paint_region = tex.b > tex.r * 2.0 && tex.b > tex.g * 1.75;
		}

		if (is_paint_region) {
			// Tint the authored paint regions instead of flattening them to one
			// color. Their luminance provides the panel and stripe contrast.
			float paint_shade = mix(0.55, 1.15, dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722)));
			ALBEDO = paint_color.rgb * paint_shade;
		} else {
			ALBEDO = tex.rgb;
		}
	} else {
		ALBEDO = tex.rgb;
	}
	
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
