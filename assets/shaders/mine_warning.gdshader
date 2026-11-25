shader_type spatial;
// The "spotted" ring round a land mine the enemy has detected (scripts/components/land_mine_model.gd).
// Unshaded and see-through; each mine sets its own glow, which is also its opacity.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform vec4 colour : source_color = vec4(1.0, 0.42, 0.06, 1.0);
instance uniform float glow = 0.0;
void fragment() {
	ALBEDO = colour.rgb * (0.8 + 0.4 * clamp(glow, 0.0, 1.0));
	ALPHA = clamp(glow, 0.0, 1.0) * colour.a;
}
