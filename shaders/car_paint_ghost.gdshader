shader_type spatial;
// Rivals are the ghosts of people you bumped, so they race as translucent cars.
// Depth is written anyway: a car is body plus wheels plus trim, and without it
// the far side of each rival blends through the near side.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/car_paint_body.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 paint_color : source_color = vec4(1.0, 0.2, 0.4, 1.0);
uniform bool use_paint_override = true;
// UV rectangle (u_min, v_min, u_max, v_max) of the palette swatch this vehicle's
// painted body panels sample from. See CarPresets.paint_region().
uniform vec4 paint_region = vec4(0.4375, 0.5, 0.5, 0.75);
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float metallic : hint_range(0.0, 1.0) = 0.2;
// How much of a rival is left where it faces the camera flat on.
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.42;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.35;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);

	// Faces turning away from the camera are the ones on the silhouette. Holding
	// them solid and lighting them in the rival's own colour keeps the car
	// readable at racing speed, which a flat wash of transparency does not.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	ALBEDO = resolve_car_albedo(UV, tex.rgb, use_paint_override, paint_region, paint_color.rgb);
	EMISSION = paint_color.rgb * rim * rim_strength;
	ALPHA = clamp(ghost_alpha + rim * (1.0 - ghost_alpha), 0.0, 1.0);
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
