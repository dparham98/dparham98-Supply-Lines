shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;
// Water of the sculpted landscape (docs/LANDSCAPE_LOOKDEV.md). Depth comes from the shore field (R of `fields`), so
// the shallows, the foam and the deep need no depth texture. Vertex colour R is 0 at the region edge, where the
// water turns into the flat map's water so the two meet.
uniform sampler2D fields : filter_linear, repeat_disable;
uniform sampler2D surface_map : source_color, filter_linear_mipmap;
uniform sampler2DArray tile_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tile_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 water_surface_mean = vec3(0.0127, 0.1046, 0.1574);
uniform vec3 shallow_color : source_color = vec3(0.13, 0.42, 0.4);
uniform vec3 foam_color : source_color = vec3(0.86, 0.92, 0.9);
// Metres from the shore at which the water reaches its deep colour, and stops showing the bed.
uniform float shallow_reach = 3.4;
uniform float clear_reach = 2.2;
// Foam: breaking lines that travel to the shore, and a thin edge on the waterline.
uniform float foam_reach = 2.6;
uniform float foam_strength = 0.75;
uniform float ripple_strength = 0.5;
const float MAP_METRES = 500.0;
const float FIELD_RANGE = 8.0;
varying float edge;
void vertex() { edge = COLOR.r; }
float hash(ivec2 p) {
 uint h = uint(p.x) * 1597334677u + uint(p.y) * 3812015801u;
 h = (h ^ (h >> 15u)) * 2246822519u;
 h = (h ^ (h >> 13u)) * 3266489917u;
 h = h ^ (h >> 16u);
 return float(h) / 4294967295.0;
}
float value_noise(vec2 p) {
 ivec2 cell = ivec2(floor(p));
 vec2 f = fract(p);
 f = f * f * (3.0 - 2.0 * f);
 return mix(mix(hash(cell), hash(cell + ivec2(1, 0)), f.x), mix(hash(cell + ivec2(0, 1)), hash(cell + ivec2(1, 1)), f.x), f.y);
}
void fragment() {
 float shore = (texture(fields, UV2).r - 0.5) * 2.0 * FIELD_RANGE;
 vec2 metres = UV * MAP_METRES;
 // The flat map's water: its tile, its tint and its slow swell.
 vec2 tile_uv = metres / 4.0;
 float pick = fract(sin(dot(floor(tile_uv), vec2(127.1, 311.7))) * 43758.5453);
 float layer = 8.0 + (pick < 0.2 ? 2.0 + floor(pick / 0.2 * 2.0) : floor((pick - 0.2) / 0.8 * 2.0));
 vec3 tint = texture(surface_map, UV).rgb / water_surface_mean;
 float difference = max(abs(tint.r - 1.0), max(abs(tint.g - 1.0), abs(tint.b - 1.0)));
 vec3 deep = texture(tile_albedo, vec3(tile_uv, layer)).rgb * mix(vec3(1.0), tint, 1.0 - smoothstep(0.25, 0.5, difference));
 float wave = sin(UV.y * 900.0 + sin(UV.x * 170.0 + TIME * 0.18) * 1.4 + TIME * 0.7);
 float small = sin(UV.y * 1900.0 + UV.x * 90.0 - TIME * 0.4);
 deep += vec3(0.018, 0.035, 0.04) * (wave * 0.30 + small * 0.10);
 vec3 flat_normal = texture(tile_normal, vec3(tile_uv, layer)).rgb;
 // Ripples: two copies of a water tile normal drifting across each other.
 vec2 drift_a = texture(tile_normal, vec3(metres / 5.3 + vec2(TIME * 0.035, TIME * 0.021), 8.0)).rg - 0.5;
 vec2 drift_b = texture(tile_normal, vec3(metres.yx / 3.1 + vec2(-TIME * 0.027, TIME * 0.04), 9.0)).rg - 0.5;
 vec2 ripple = (drift_a + drift_b) * ripple_strength;
 // Shallows show the bed through clear green water.
 float shallow = 1.0 - smoothstep(0.0, shallow_reach, shore);
 vec3 color = mix(deep, shallow_color, shallow * 0.75);
 float alpha = mix(0.34, 1.0, smoothstep(0.0, clear_reach, shore)) * smoothstep(-0.12, 0.06, shore);
 // Foam lines roll in, break up along their length and fade before the next one.
 float broken = value_noise(metres * 0.55 + vec2(TIME * 0.05, 0.0));
 float phase = shore * 2.4 + TIME * 0.55 + broken * 2.6;
 float line = smoothstep(0.82, 0.98, sin(phase) * 0.5 + 0.5) * smoothstep(0.35, 0.6, value_noise(metres * 1.7 - vec2(0.0, TIME * 0.08)));
 float lines = line * (1.0 - smoothstep(0.4, foam_reach, shore)) * smoothstep(-0.05, 0.25, shore);
 float lap = sin(TIME * 0.9 + broken * 6.0) * 0.07;
 float rim = (1.0 - smoothstep(0.03, 0.3 + broken * 0.22, shore + lap)) * smoothstep(-0.14, 0.0, shore + lap);
 float foam = clamp(max(lines * 0.8, rim) * foam_strength, 0.0, 1.0);
 color = mix(color, foam_color, foam);
 alpha = max(alpha, foam);
 // At the region edge: the flat map's water exactly.
 ALBEDO = mix(deep, color, edge);
 ALPHA = mix(1.0, alpha, edge);
 ROUGHNESS = mix(0.33, mix(0.14, 0.6, foam), edge);
 SPECULAR = 0.5;
 NORMAL_MAP = vec3(mix(flat_normal.xy, vec2(0.5) + ripple, edge), 1.0);
}
