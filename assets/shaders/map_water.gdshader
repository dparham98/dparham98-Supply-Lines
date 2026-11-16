shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;
// The surface of a sunken basin (scripts/tools/build_water_basin.gd). It reads how far the bed lies below it, so the
// shallows are clear, the deep is dark, and foam gathers wherever something breaks the surface: the bank, a rock,
// a reed.
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 water_shallow : source_color = vec3(0.3, 0.5, 0.45);
uniform vec3 water_deep : source_color = vec3(0.11, 0.27, 0.34);
// Metres of water at which the bed is lost from view, and at which the colour is fully the deep one.
uniform float clear_metres = 0.85;
uniform float deep_metres = 1.2;
uniform float ripple_strength = 0.5;
uniform float foam_strength = 0.5;
// Metres the surface rises and falls, which makes its edge lap at the bank.
uniform float lap_metres = 0.02;
const float MAP_METRES = 500.0;
varying vec2 metres;
// The noise of terrain_surface.gdshader.
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
float layered_noise(vec2 p, int layers) {
 float total = 0.0;
 float weight = 0.5;
 float sum = 0.0;
 for (int i = 0; i < layers; i++) {
  total += value_noise(p) * weight;
  sum += weight;
  weight *= 0.5;
  p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(17.3, 9.1);
 }
 return total / sum;
}
void vertex() {
 metres = UV * MAP_METRES;
 // Each stretch of water in its own time.
 VERTEX.y += sin(TIME * 0.8 + layered_noise(metres * 0.11, 2) * 25.0) * lap_metres;
}
void fragment() {
 // Metres of water under this point, from what is already drawn behind it.
 float raw = texture(depth_texture, SCREEN_UV).r;
 vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
 behind.xyz /= behind.w;
 vec3 ray = PROJECTION_MATRIX[3][3] > 0.5 ? vec3(0.0, 0.0, -1.0) : normalize(VERTEX);
 float along = max(0.0, (VERTEX.z - behind.z) / max(-ray.z, 0.05));
 float depth = along * abs((INV_VIEW_MATRIX * vec4(ray, 0.0)).y);
 float deepness = smoothstep(0.0, deep_metres, depth);
 vec3 color = mix(water_shallow, water_deep, deepness);
 color *= 0.88 + 0.24 * layered_noise(metres / 26.0 + vec2(5.0, 1.0), 2);
 // Ripples: two layers of small waves crossing each other.
 vec2 first = metres * 0.85 + vec2(TIME * 0.21, TIME * 0.12);
 vec2 second = metres * 2.3 + vec2(-TIME * 0.16, TIME * 0.27);
 float level = value_noise(first) + 0.45 * value_noise(second);
 vec2 slope = vec2(value_noise(first + vec2(0.1, 0.0)) + 0.45 * value_noise(second + vec2(0.1, 0.0)) - level, value_noise(first + vec2(0.0, 0.1)) + 0.45 * value_noise(second + vec2(0.0, 0.1)) - level) / 0.1;
 vec2 bent = -slope * 0.22 * ripple_strength * (0.35 + 0.65 * deepness);
 color *= 1.0 + (level - 0.72) * 0.16;
 // Foam: a broken line where the water is thinnest, and a fainter one that drifts out from it.
 float broken = layered_noise(metres * 1.6 + vec2(TIME * 0.05, -TIME * 0.04), 2);
 float edge = 1.0 - smoothstep(0.02, 0.13, depth);
 float drift = fract(TIME * 0.07 + layered_noise(metres * 0.07, 2) * 3.0);
 float ring = (1.0 - smoothstep(0.0, 0.05, abs(depth - 0.16 - drift * 0.22))) * (1.0 - drift) * 0.5;
 float foam = clamp(smoothstep(0.42, 0.62, broken * (0.45 + edge)) * edge * 1.4 + ring * smoothstep(0.5, 0.7, broken), 0.0, 1.0) * foam_strength;
 ALBEDO = mix(color, vec3(0.78, 0.84, 0.82), foam);
 NORMAL_MAP = vec3(0.5 + bent * min(1.0, 0.42 / max(length(bent), 0.001)), 1.0);
 ROUGHNESS = mix(0.1, 0.8, foam);
 // Thin water is nearly clear; the last few centimetres fade out so the edge is soft.
 ALPHA = max(mix(0.3, 0.97, smoothstep(0.0, clear_metres, depth)), foam) * smoothstep(0.0, 0.035, depth);
}
