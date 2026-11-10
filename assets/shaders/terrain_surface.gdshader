shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D surface_map : source_color, filter_linear_mipmap;
uniform sampler2D category_map : filter_nearest;
uniform sampler2D cleared_cells : hint_default_black, filter_nearest, repeat_disable;
// Ground tiles, packed by scripts/tools/build_ground_tile_arrays.gd: layers 0-3 grass, 4-7 desert, 8-11 water.
uniform sampler2DArray tile_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tile_normal : filter_linear_mipmap_anisotropic, repeat_enable;
// Metres of ground one tile covers.
uniform float tile_metres = 4.0;
// Share of tiles that use the two feature variants of a set (flowers and dirt, rocks and cracks, sparkle and foam).
uniform float feature_share = 0.2;
// How much of the map's soft colour variation shows through the tiles, and that map's mean colours.
uniform float surface_tint = 1.0;
uniform vec3 grass_surface_mean = vec3(0.097, 0.161, 0.041);
uniform vec3 desert_surface_mean = vec3(0.586, 0.399, 0.137);
uniform vec3 water_surface_mean = vec3(0.0127, 0.1046, 0.1574);
uniform vec3 forest_surface_mean = vec3(0.044, 0.108, 0.027);
uniform vec3 mountain_surface_mean = vec3(0.0902, 0.0942, 0.0736);
// Desert tiles darkened to stony ground, for the mountain foot where the sculpted mesh does not cover it.
uniform vec3 stony_tint = vec3(0.2, 0.22, 0.38);
// Distance from the desert and grass border, from scripts/tools/build_ground_blend_map.gd: 0.5 is the border.
uniform sampler2D ground_blend : filter_linear, repeat_disable;
// Metres the drawn border may wander either side of its smoothed line, and how wide the crossfade is.
uniform float border_wander = 0.65;
uniform float border_softness = 0.28;
// Metres of grass beside desert that fade towards dry straw, and how far they fade.
uniform float dry_margin = 6.0;
uniform float dry_strength = 0.55;
// Large colour patches across the map, on grass and on desert.
uniform float macro_strength = 1.0;
// A second, larger copy of the tile pattern, which breaks up the 4 m repeat.
uniform float breakup_strength = 0.55;
// Gentle rolling relief lit by the sun, on grass and on desert.
uniform float grass_relief = 0.5;
uniform float desert_relief = 1.0;
const float MAP_METRES = 500.0;
const float BLEND_RANGE = 8.0;
// All tiles of a set share their borders, so any variant can sit beside any other. UVs stay continuous
// across tiles and only the layer changes, which keeps mip selection seamless.
float tile_layer(vec2 tile_uv, float first_layer) {
 float pick = fract(sin(dot(floor(tile_uv), vec2(127.1, 311.7))) * 43758.5453);
 if (pick < feature_share) { return first_layer + 2.0 + floor(pick / feature_share * 2.0); }
 return first_layer + floor((pick - feature_share) / (1.0 - feature_share) * 2.0);
}
// Whole-number hash. Both cells that share a grid corner must get exactly the same value for it. A float hash
// amplifies rounding differences until they do not, which draws a straight seam along the cell edge.
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
// Layered noise in the range 0-1. Each layer is turned so no grid shows.
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
// One ground set at this position: its tile and normal, with the map tint and the larger breakup pattern.
void ground_set(vec2 tile_uv, float first_layer, vec3 map_color, vec3 mean, float map_tint, float breakup, out vec3 albedo, out vec3 normal_rgb) {
 vec3 layer_uv = vec3(tile_uv, tile_layer(tile_uv, first_layer));
 // Tint by the soft variation of the map image. Near a border that blurry image holds the colour of the
 // neighbouring ground, which would show as a band, so large differences from the mean are ignored.
 vec3 tint = map_color / mean;
 float difference = max(abs(tint.r - 1.0), max(abs(tint.g - 1.0), abs(tint.b - 1.0)));
 albedo = texture(tile_albedo, layer_uv).rgb * mix(vec3(1.0), tint, map_tint * (1.0 - smoothstep(0.25, 0.5, difference)));
 normal_rgb = texture(tile_normal, layer_uv).rgb;
 // Plain variants only, at a scale that never lines up with the tiles, so the larger copy is seamless.
 vec3 large = texture(tile_albedo, vec3(tile_uv.yx * 0.293 + vec2(0.37, 0.11), first_layer)).rgb;
 vec3 average = textureLod(tile_albedo, vec3(0.5, 0.5, first_layer), 9.0).rgb;
 albedo *= mix(vec3(1.0), clamp(large / max(average, vec3(0.01)), vec3(0.5), vec3(1.6)), breakup);
}
void fragment() {
 vec3 color = texture(surface_map, UV).rgb;
 float terrain = round(texture(category_map, UV).r * 255.0);
 vec3 normal_map = vec3(0.5, 0.5, 1.0);
 ROUGHNESS = terrain == 1.0 ? 0.33 : 0.96;
 vec2 tile_uv = UV * MAP_METRES / tile_metres;
 vec2 metres = UV * MAP_METRES;
 if (terrain == 0.0 || terrain == 2.0 || terrain == 3.0) {
  // Open ground: grass (or forest floor) and desert crossfade along a wandering line.
  float signed_metres = (texture(ground_blend, UV).r - 0.5) * 2.0 * BLEND_RANGE;
  // The map image traces the old stepped border, so its tint fades out beside the border.
  float map_tint = surface_tint * smoothstep(1.5, 4.0, abs(signed_metres));
  vec3 grass; vec3 grass_normal; vec3 desert; vec3 desert_normal;
  ground_set(tile_uv, 0.0, color, terrain == 3.0 ? forest_surface_mean : grass_surface_mean, map_tint, breakup_strength, grass, grass_normal);
  ground_set(tile_uv, 4.0, color, desert_surface_mean, map_tint, breakup_strength, desert, desert_normal);
  float wander = (layered_noise(metres * 0.32, 4) - 0.5) * 4.0 * border_wander;
  float softness = max(border_softness, fwidth(signed_metres) * 1.5);
  float into_desert = smoothstep(-softness, softness, signed_metres + wander);
  // Colour patches: broad drifts, with smaller drier or richer areas inside them.
  float broad = layered_noise(metres / 64.0 + vec2(3.1, 7.7), 3);
  float patches = layered_noise(metres / 17.0 + vec2(11.9, 2.3), 3);
  vec3 grass_shift = mix(vec3(0.78, 0.84, 0.72), vec3(1.2, 1.14, 0.92), smoothstep(0.28, 0.72, broad));
  grass *= mix(vec3(1.0), grass_shift, macro_strength);
  // Dry straw in patches and on the strip of grass beside desert.
  float dry = max(smoothstep(0.56, 0.74, patches) * 0.45, (1.0 - smoothstep(0.0, dry_margin, -signed_metres + wander)) * dry_strength);
  grass = mix(grass, grass * vec3(1.55, 1.18, 0.62), dry * macro_strength);
  vec3 desert_shift = mix(vec3(0.84, 0.79, 0.74), vec3(1.12, 1.08, 1.02), smoothstep(0.26, 0.74, broad));
  desert *= mix(vec3(1.0), desert_shift, macro_strength);
  desert *= mix(vec3(1.0), vec3(0.86, 0.82, 0.76), (1.0 - smoothstep(0.34, 0.6, patches)) * 0.7 * macro_strength);
  color = mix(grass, desert, into_desert);
  normal_map = mix(grass_normal, desert_normal, into_desert);
  // Rolling relief from the slope of a smooth height field, and a little colour from its height.
  float relief = mix(grass_relief, desert_relief, into_desert);
  vec2 relief_uv = metres / 22.0;
  float height = layered_noise(relief_uv, 3);
  vec2 slope = vec2(layered_noise(relief_uv + vec2(0.06, 0.0), 3) - height, layered_noise(relief_uv + vec2(0.0, 0.06), 3) - height) / 0.06;
  // The length limit keeps the result a valid normal; past it the surface renders black.
  vec2 bent = normal_map.xy - 0.5 - slope * 0.1 * relief;
  normal_map.xy = 0.5 + bent * min(1.0, 0.42 / max(length(bent), 0.001));
  color *= 1.0 + (height - 0.5) * 0.12 * relief;
 } else if (terrain == 1.0 || terrain == 4.0) {
  // Water, and the mountain foot in darkened desert tiles.
  ground_set(tile_uv, terrain == 4.0 ? 4.0 : 8.0, color, terrain == 4.0 ? mountain_surface_mean : water_surface_mean, surface_tint, 0.0, color, normal_map);
  if (terrain == 4.0) { color *= stony_tint; }
 }
 if (terrain == 1.0) {
  float wave = sin(UV.y * 900.0 + sin(UV.x * 170.0 + TIME * 0.18) * 1.4 + TIME * 0.7);
  float small = sin(UV.y * 1900.0 + UV.x * 90.0 - TIME * 0.4);
  color += vec3(0.018, 0.035, 0.04) * (wave * 0.30 + small * 0.10);
 }
 if (texture(cleared_cells, UV).r > 0.5) { color = vec3(0.28, 0.22, 0.12); ROUGHNESS = 0.96; normal_map = vec3(0.5, 0.5, 1.0); }
 ALBEDO = color;
 NORMAL_MAP = normal_map;
}
