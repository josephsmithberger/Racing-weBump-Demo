shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/car_paint_body.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 paint_color : source_color = vec4(1.0, 0.2, 0.4, 1.0);
uniform bool use_paint_override = true;
// UV rectangle (u_min, v_min, u_max, v_max) of the palette swatch this vehicle's
// painted body panels sample from. See CarPresets.paint_region().
uniform vec4 paint_region = vec4(0.4375, 0.5, 0.5, 0.75);
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float metallic : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);

	ALBEDO = resolve_car_albedo(UV, tex.rgb, use_paint_override, paint_region, paint_color.rgb);
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
