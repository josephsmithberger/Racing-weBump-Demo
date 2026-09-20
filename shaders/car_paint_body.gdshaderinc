// Shared paint resolution for the car shaders, so the solid and ghost versions
// cannot drift apart.
//
// The model palette encodes paint and functional details in the same mesh, so
// the painted panels are the faces that sample this vehicle's paint swatch.
// Classifying by texel hue instead would depend on whether the renderer hands
// the shader linear or sRGB texels, which Forward+ and Compatibility disagree on.
vec3 resolve_car_albedo(vec2 uv, vec3 texel, bool use_override, vec4 region, vec3 paint) {
	bool is_paint_region = use_override
		&& all(greaterThanEqual(uv, region.xy))
		&& all(lessThan(uv, region.zw));

	if (!is_paint_region) {
		return texel;
	}

	// Each swatch is a vertical light-to-dark ramp, and where a face sits in it
	// is the panel and stripe contrast the artist authored. Reading the ramp from
	// UV rather than from the texel keeps the shading identical on every renderer.
	float ramp = (uv.y - region.y) / max(region.w - region.y, 0.0001);
	return paint * mix(0.82, 0.61, clamp(ramp, 0.0, 1.0));
}
