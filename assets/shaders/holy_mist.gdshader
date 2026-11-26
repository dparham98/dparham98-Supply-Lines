shader_type spatial;
// The Grail Sentinel's Mist (docs/MIST_AND_SLOW.md): one layer of a low rolling cloud, drawn on a flat disc of
// unit radius. Soft noise rolls and swirls about the centre; the edge frays into wisps; faint gold motes drift
// through it. `fade` (0..1, per instance, from mist_look.gd) billows it in and thins it out: as it falls, the
// noise is eaten away before the whole layer goes, so the cloud breaks up rather than simply turning transparent.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 mist_color : source_color = vec4(0.86, 0.88, 0.86, 1.0);
uniform vec4 shade_color : source_color = vec4(0.62, 0.66, 0.70, 1.0);
uniform vec4 mote_color : source_color = vec4(1.0, 0.84, 0.42, 1.0);
// Peak opacity: enough to read as cover from the RTS camera, low enough that the ground shows through.
uniform float density = 0.5;
uniform float swirl_speed = 0.08;
uniform float roll_speed = 0.12;
uniform float noise_scale = 3.2;
uniform float mote_density = 26.0;
instance uniform float fade = 1.0;
instance uniform float layer_seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(17.1, 9.2); a *= 0.5; }
	return v;
}
vec2 rot(vec2 p, float a) { float c = cos(a), s = sin(a); return vec2(c * p.x - s * p.y, s * p.x + c * p.y); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// Inner parts turn faster than the rim, which twists the noise into a slow swirl.
	float t = TIME + layer_seed * 31.0;
	vec2 q = rot(p, t * swirl_speed * (1.4 - r) + layer_seed * 2.0);
	vec2 drift = vec2(t * roll_speed, t * roll_speed * 0.6);
	float n = fbm(q * noise_scale + drift + layer_seed * 7.0);
	float n2 = fbm(q * noise_scale * 2.3 - drift * 1.7 + 3.0);
	float cloud = n * 0.65 + n2 * 0.35;
	// A frayed rim: the edge sits further out where the noise is thick.
	float rim = 1.0 - smoothstep(0.62 + 0.3 * cloud, 1.0, r);
	// Thinning eats the thin parts first.
	float eat = mix(0.75, 0.18, fade);
	float body = smoothstep(eat, eat + 0.35, cloud) * rim;
	float alpha = body * density * smoothstep(0.0, 0.35, fade);
	vec3 col = mix(shade_color.rgb, mist_color.rgb, smoothstep(0.3, 0.8, n2));
	// Gold motes: sparse cells, each a soft point that twinkles.
	vec2 mp = rot(p, t * swirl_speed * 0.5) * mote_density + vec2(0.0, t * 0.4);
	vec2 cell = floor(mp);
	vec2 off = vec2(hash(cell + layer_seed), hash(cell + 9.1 + layer_seed)) * 0.8 + 0.1;
	float d = length(fract(mp) - off);
	float live = step(0.86, hash(cell + 4.7));
	float twinkle = 0.5 + 0.5 * sin(t * 3.0 + hash(cell) * 40.0);
	float mote = live * twinkle * (1.0 - smoothstep(0.03, 0.12, d)) * rim * fade;
	ALBEDO = mix(col, mote_color.rgb, clamp(mote * 1.5, 0.0, 1.0));
	ALPHA = clamp(alpha + mote * 0.8, 0.0, 1.0);
}
