shader_type spatial;
// A land mine's fuse lamp (scripts/components/land_mine_model.gd). Unshaded so it reads at RTS
// zoom; each mine sets its own glow: 0 is dark, 1 full, above 1 overbright.
render_mode unshaded, cull_back, shadows_disabled;
uniform vec4 colour : source_color = vec4(1.0, 0.16, 0.04, 1.0);
uniform vec4 dim_colour : source_color = vec4(0.22, 0.03, 0.01, 1.0);
instance uniform float glow = 0.0;
void fragment() {
	float g = clamp(glow, 0.0, 1.5);
	ALBEDO = mix(dim_colour.rgb, colour.rgb, clamp(g, 0.0, 1.0)) * (1.0 + max(g - 1.0, 0.0));
}
