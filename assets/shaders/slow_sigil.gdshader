shader_type spatial;
// The Grail Sentinel's Slow (docs/MIST_AND_SLOW.md): a blue and gold sigil laid on the ground, drawn on a flat quad
// whose edge is the field's radius. An outer double ring of gold, a band of runes between, and an inner
// eight-pointed star of blue that turns slowly. The whole pulses gently. `draw_in` and `fade` (0..1, per instance, from
// spell_look.gd) draw it in from the rim and let it die away.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 gold : source_color = vec4(1.0, 0.78, 0.32, 1.0);
uniform vec4 blue : source_color = vec4(0.35, 0.62, 1.0, 1.0);
uniform float strength = 0.95;
uniform float turn_speed = 0.35;
uniform float pulse_speed = 3.2;
instance uniform float fade = 1.0;
instance uniform float draw_in = 1.0;

float hash(float n) { return fract(sin(n * 91.345) * 47453.5453); }
float band(float x, float centre, float width) { return 1.0 - smoothstep(width * 0.5, width * 0.5 + 0.008, abs(x - centre)); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed);
	// Gold double ring at the edge.
	float rings = band(r, 0.95, 0.04) + band(r, 0.86, 0.02);
	// Runes: short strokes of varied length and lean in the band between the rings, turning against the star.
	float ra = a - TIME * turn_speed * 0.5;
	float seg = floor((ra / 6.28318 + 0.5) * 40.0);
	float u = fract((ra / 6.28318 + 0.5) * 40.0);
	float h = hash(seg);
	float stroke = (1.0 - smoothstep(0.07, 0.13, abs(u - 0.5 - (r - 0.9) * (h - 0.5) * 6.0)));
	float runes = stroke * band(r, 0.905, 0.04 + 0.03 * h) * step(0.2, h);
	// The inner star: eight points, blue, turning.
	float sa = a + TIME * turn_speed;
	float k = abs(fract(sa / 6.28318 * 8.0) - 0.5) * 2.0;
	float star_edge = mix(0.7, 0.28, k);
	float star = band(r, star_edge, 0.028) * step(0.2, r);
	float inner = band(r, 0.28, 0.028) + band(r, 0.7, 0.018);
	// A faint blue wash, brighter toward the rim, so the area reads as a whole.
	float wash = smoothstep(0.2, 0.95, r) * (1.0 - smoothstep(0.95, 1.0, r)) * 0.22;
	// Mixed, not added, so the lines keep their colour on bright sand as well as on grass.
	float g = clamp(rings + runes, 0.0, 1.0);
	float b = clamp(star + inner * 0.8, 0.0, 1.0);
	vec3 col = mix(blue.rgb * 0.55, blue.rgb, b);
	col = mix(col, gold.rgb, g);
	float cover = clamp(max(g, b) + wash * 1.4, 0.0, 1.0);
	// Drawn in from the rim as fade rises, then dimmed as it falls.
	float edge = 1.0 - draw_in * 1.1;
	float drawn = smoothstep(edge, edge + 0.08, r);
	float show = drawn * fade * strength * pulse;
	ALBEDO = col * (0.85 + 0.3 * pulse);
	ALPHA = clamp(cover * show, 0.0, 1.0);
}
