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
// Mine sites (category 7): the rust that stains their stone.
uniform vec3 mine_site_stain = vec3(0.36, 0.14, 0.07);
// Coal cells (category 6): how dark the seam is drawn.
uniform vec3 coal_shade = vec3(0.1, 0.1, 0.125);
// Distance from the desert and grass border, from scripts/tools/build_ground_blend_map.gd: 0.5 is the border.
uniform sampler2D ground_blend : filter_linear, repeat_disable;
// The same image's green channel is the distance from the shoreline: 0.5 is the shore, above it is water.
// Metres the drawn shore may wander, and the colours and motion of the water drawn from it.
uniform float shore_wander = 0.35;
// Metres the drawn shore sits inside the Water cells. With the wander it keeps drawn water off ground that units
// walk on; the blue channel holds the cells' own edge, which the drawn shore never crosses. scripts/tools/
// shore_field.gd uses the same two numbers.
uniform float shore_inset = 0.8;
// Above 0.5 the water is sunk (scripts/tools/build_water_basin.gd): this shader then draws only the ground and the
// bed, on the basin mesh where its second UV marks it, and a separate surface mesh draws the water.
uniform float water_sunk = 0.0;
uniform vec3 water_shallow = vec3(0.07, 0.2, 0.17);
uniform vec3 water_deep = vec3(0.012, 0.06, 0.095);
// Metres from the shore at which the bed is lost from view.
uniform float water_depth_metres = 5.0;
// Wet sand or mud on the strip of ground beside the water, and how wide that strip is.
uniform vec3 bank_color = vec3(0.2, 0.155, 0.095);
uniform float bank_metres = 1.4;
uniform float foam_strength = 0.6;
uniform float ripple_strength = 0.5;
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
// Part of the map drawn by the sculpted landscape instead (docs/LANDSCAPE_LOOKDEV.md), as UV min and max. Set by
// scripts/tools/build_landscape.gd; all zero draws the whole map here.
uniform vec4 landscape_region = vec4(0.0);
// Open ground only (grass, forest floor, desert): saturation and brightness, so the ground sits behind units and
// buildings. 1.0 leaves it as drawn.
uniform float ground_saturation = 1.0;
uniform float ground_value = 1.0;
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
 if (UV.x > landscape_region.x && UV.y > landscape_region.y && UV.x < landscape_region.z && UV.y < landscape_region.w) { discard; }
 vec3 color = texture(surface_map, UV).rgb;
 float terrain = round(texture(category_map, UV).r * 255.0);
 vec3 normal_map = vec3(0.5, 0.5, 1.0);
 ROUGHNESS = terrain == 1.0 ? 0.33 : 0.96;
 vec2 tile_uv = UV * MAP_METRES / tile_metres;
 vec2 metres = UV * MAP_METRES;
 vec4 blend = texture(ground_blend, UV);
 // Metres into the water. The cells give a staircase; the blurred distance and a little noise give a shoreline.
 float shore = min((blend.g - 0.5) * 2.0 * BLEND_RANGE + (layered_noise(metres * 0.19 + vec2(41.0, 7.0), 3) - 0.5) * 4.0 * shore_wander - shore_inset, blend.b * BLEND_RANGE - 2.0);
 bool land = terrain == 0.0 || terrain == 2.0 || terrain == 3.0;
 // Sunk water: the flat ground stops just past the shore and the basin mesh carries on from there. They overlap
 // by a few centimetres where both are level, so no gap can open between them.
 bool basin = UV2.x > 0.5;
 if (water_sunk > 0.5 && (basin ? shore < -0.2 : shore > -0.15)) { discard; }
 if (land || (terrain == 1.0 && (shore < 3.0 || basin))) {
  // Open ground: grass (or forest floor) and desert crossfade along a wandering line. Water cells near the shore
  // draw it too, as the bed seen through the shallows and wherever the drawn shore runs inside them.
  float signed_metres = (blend.r - 0.5) * 2.0 * BLEND_RANGE;
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
  color = mix(vec3(dot(color, vec3(0.2126, 0.7152, 0.0722))), color, ground_saturation) * ground_value;
 } else if (terrain == 4.0 || terrain == 7.0) {
  // The mountain foot in darkened desert tiles. A mine site is the same stone, stained with rust.
  ground_set(tile_uv, 4.0, color, mountain_surface_mean, terrain == 4.0 ? surface_tint : 0.0, 0.0, color, normal_map);
  color *= stony_tint;
  if (terrain == 7.0) { color = mix(color * 1.5, mine_site_stain * dot(color, vec3(4.0)), 0.55); }
 } else if (terrain == 6.0) {
  // Coal seam: the cracked desert tiles with their colour taken out, darkened to black rock.
  vec3 seam;
  ground_set(tile_uv, 4.0, desert_surface_mean, desert_surface_mean, 0.0, 0.0, seam, normal_map);
  // The seam lies in the ground: black, broken rock with a dull shine on some of its faces.
  float facets = value_noise(metres * 3.1);
  color = vec3(dot(seam, vec3(0.3, 0.5, 0.2))) * coal_shade * mix(0.55, 1.5, facets) * vec3(0.92, 0.96, 1.08);
  ROUGHNESS = mix(0.7, 0.28, smoothstep(0.55, 0.8, facets));
 }
 if (terrain == 1.0 || (land && shore > -bank_metres - 0.5)) {
  // The bank: ground turns to wet sand towards the water, darkest at the waterline.
  float wet = smoothstep(-bank_metres, -0.15, shore);
  vec3 bank = bank_color * (0.8 + 0.4 * value_noise(metres * 2.3));
  vec3 bed = mix(color, bank * mix(1.0, 0.72, smoothstep(-0.5, 0.0, shore)), wet * 0.85);
  ROUGHNESS = mix(ROUGHNESS, 0.55, wet * 0.8);
  if (water_sunk > 0.5) {
   // The bed, seen through the surface mesh: sand at the bank, silt further down.
   color = mix(bed, bed * vec3(0.5, 0.62, 0.5), smoothstep(0.4, 4.0, shore));
  } else {
  // The edge of the water laps in and out, each stretch of shore in its own time.
  float lap = sin(TIME * 0.8 + layered_noise(metres * 0.11, 2) * 25.0) * 0.14;
  float cover = smoothstep(0.0, 0.3, shore + lap);
  // Clear over the bed in the shallows, then deepening.
  float depth = smoothstep(0.0, water_depth_metres, shore);
  vec3 water = mix(mix(bed * vec3(0.5, 0.78, 0.7), water_shallow, 0.35 + 0.45 * smoothstep(0.0, 1.6, shore)), water_deep, depth);
  water *= 0.88 + 0.24 * layered_noise(metres / 26.0 + vec2(5.0, 1.0), 2);
  // Ripples: two layers of small waves crossing each other.
  vec2 first = metres * 0.85 + vec2(TIME * 0.21, TIME * 0.12);
  vec2 second = metres * 2.3 + vec2(-TIME * 0.16, TIME * 0.27);
  float level = value_noise(first) + 0.45 * value_noise(second);
  vec2 slope = vec2(value_noise(first + vec2(0.1, 0.0)) + 0.45 * value_noise(second + vec2(0.1, 0.0)) - level, value_noise(first + vec2(0.0, 0.1)) + 0.45 * value_noise(second + vec2(0.0, 0.1)) - level) / 0.1;
  vec2 bent = -slope * 0.22 * ripple_strength * (0.35 + 0.65 * depth);
  vec3 ripple = vec3(0.5 + bent * min(1.0, 0.42 / max(length(bent), 0.001)), 1.0);
  water *= 1.0 + (level - 0.72) * 0.16;
  // Foam: a broken line at the edge, and a fainter one that drifts out from it.
  float broken = layered_noise(metres * 1.6 + vec2(TIME * 0.05, -TIME * 0.04), 2);
  float edge = 1.0 - smoothstep(0.0, 0.75, shore + lap);
  float drift = fract(TIME * 0.07 + layered_noise(metres * 0.07, 2) * 3.0);
  float ring = (1.0 - smoothstep(0.0, 0.22, abs(shore - 0.5 - drift * 1.6))) * (1.0 - drift) * 0.55;
  float foam = cover * clamp(smoothstep(0.42, 0.62, broken * (0.45 + edge)) * edge * 1.4 + ring * smoothstep(0.5, 0.7, broken), 0.0, 1.0) * foam_strength;
  color = mix(mix(bed, water, cover), vec3(0.78, 0.84, 0.82), foam);
  normal_map = mix(normal_map, ripple, cover * (1.0 - foam));
  ROUGHNESS = mix(mix(ROUGHNESS, 0.1, cover), 0.8, foam);
  }
 }
 if (texture(cleared_cells, UV).r > 0.5) { color = vec3(0.28, 0.22, 0.12); ROUGHNESS = 0.96; normal_map = vec3(0.5, 0.5, 1.0); }
 ALBEDO = color;
 NORMAL_MAP = normal_map;
}
