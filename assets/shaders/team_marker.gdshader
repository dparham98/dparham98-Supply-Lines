shader_type spatial;
// Team marker (docs/TEAM_MARKERS.md): a flat rounded shape on the ground under a unit, a faint fill
// with a solid rim in its side's colour, so both sides read apart at any zoom.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Set by unit_agent.gd from scripts/units/team_colors.gd.
instance uniform vec4 team_color : source_color = vec4(0.37, 0.82, 0.54, 1.0);
// Half the marker's width and length in metres. Each unit scene sets it to match its PlaneMesh.
instance uniform vec2 half_size = vec2(0.85, 0.85);
// Rim width in metres; it never thins below about one and a half pixels when zoomed out.
uniform float rim_metres = 0.16;
uniform float rim_alpha = 0.9;
uniform float fill_alpha = 0.2;
varying vec2 local;
void vertex() {
 local = VERTEX.xz;
}
void fragment() {
 // Signed distance to a rectangle with fully rounded ends: negative inside.
 float radius = min(half_size.x, half_size.y);
 vec2 q = abs(local) - (half_size - vec2(radius));
 float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
 float aa = max(fwidth(d), 0.0001);
 float rim = max(rim_metres, aa * 1.5);
 float inside = 1.0 - smoothstep(-aa, 0.0, d);
 float on_rim = smoothstep(-rim - aa, -rim, d);
 ALBEDO = team_color.rgb;
 ALPHA = inside * mix(fill_alpha, rim_alpha, on_rim) * team_color.a;
}
