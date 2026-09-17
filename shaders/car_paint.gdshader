shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

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

	// The model palette encodes paint and functional details in the same mesh, so
	// the painted panels are the faces that sample this vehicle's paint swatch.
	// Classifying by texel hue instead would depend on whether the renderer hands
	// the shader linear or sRGB texels, which Forward+ and Compatibility disagree on.
	bool is_paint_region = use_paint_override
		&& all(greaterThanEqual(UV, paint_region.xy))
		&& all(lessThan(UV, paint_region.zw));

	if (is_paint_region) {
		// Each swatch is a vertical light-to-dark ramp, and where a face sits in it
		// is the panel and stripe contrast the artist authored. Reading the ramp from
		// UV rather than from the texel keeps the shading identical on every renderer.
		float ramp = (UV.y - paint_region.y) / max(paint_region.w - paint_region.y, 0.0001);
		ALBEDO = paint_color.rgb * mix(0.82, 0.61, clamp(ramp, 0.0, 1.0));
	} else {
		ALBEDO = tex.rgb;
	}

	ROUGHNESS = roughness;
	METALLIC = metallic;
}
