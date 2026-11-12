shader_type spatial;
render_mode cull_disabled;
// A unit being assembled in the Tank Factory (docs/TANK_FACTORY_MODEL.md): everything above cut_height (world Y)
// is not there yet, the rest is bare primer, and a glowing weld seam runs along the cut.
uniform vec4 primer : source_color = vec4(0.58,0.56,0.51,1.0);
uniform vec4 weld : source_color = vec4(1.0,0.55,0.16,1.0);
uniform float cut_height = 0.0;
uniform float seam = 0.06;
uniform float glow_energy = 4.0;
varying float world_y;
void vertex() {
	world_y = (MODEL_MATRIX*vec4(VERTEX,1.0)).y;
}
void fragment() {
	if (world_y > cut_height) discard;
	float glow = 1.0-smoothstep(0.0,seam,cut_height-world_y);
	ALBEDO = mix(primer.rgb,weld.rgb,glow);
	EMISSION = weld.rgb*glow*glow_energy;
	METALLIC = 0.3;
	ROUGHNESS = 0.6;
}
