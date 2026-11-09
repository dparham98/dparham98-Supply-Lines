// Runs the chainsaw teeth along the bar. Apply as a ShaderMaterial on the
// "chainsaw_teeth" node (Geometry > Material Override).
// The mesh is authored for this: local +Y runs along the bar from its root,
// local X runs across it, and teeth are evenly spaced by `pitch`.
shader_type spatial;

uniform float pitch = 0.075;     // spacing between teeth, metres
uniform float tip_start = 0.505; // teeth start tucking into the bar here
uniform float tip_end = 0.565;   // fully tucked here (bar nose)
uniform float tuck = 0.45;       // tooth width kept once fully tucked
uniform vec3 albedo = vec3(0.035, 0.037, 0.023); // same as mat_gunmetal (linear)

// Teeth spacings per second, set per unit. 0 = motor off.
// Stay near 8-12: much faster strobes or appears to run backward.
instance uniform float speed = 0.0;

void vertex() {
	float phase = fract(TIME * speed) * pitch;
	// The +X row is the cutting edge on a downward chop, so it pulls back
	// toward the gauntlet; the other row runs out to the nose.
	VERTEX.y += VERTEX.x > 0.0 ? pitch - phase : phase;

	float t = smoothstep(tip_start, tip_end, VERTEX.y);
	VERTEX.x *= mix(1.0, tuck, t);
	VERTEX.y = min(VERTEX.y, tip_end);
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.9;
}
