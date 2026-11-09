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
const float MAP_METRES = 500.0;
// All tiles of a set share their borders, so any variant can sit beside any other. UVs stay continuous
// across tiles and only the layer changes, which keeps mip selection seamless.
float tile_layer(vec2 tile_uv, float first_layer) {
 float pick = fract(sin(dot(floor(tile_uv), vec2(127.1, 311.7))) * 43758.5453);
 if (pick < feature_share) { return first_layer + 2.0 + floor(pick / feature_share * 2.0); }
 return first_layer + floor((pick - feature_share) / (1.0 - feature_share) * 2.0);
}
void fragment() {
 vec3 color = texture(surface_map, UV).rgb;
 float terrain = round(texture(category_map, UV).r * 255.0);
 vec3 normal_map = vec3(0.5, 0.5, 1.0);
 ROUGHNESS = terrain == 1.0 ? 0.33 : 0.96;
 // Grass, water, desert and forest floor are tiled; forest floor uses the grass set.
 if (terrain <= 3.0) {
  float first_layer = terrain == 2.0 ? 4.0 : (terrain == 1.0 ? 8.0 : 0.0);
  vec3 mean = terrain == 0.0 ? grass_surface_mean : (terrain == 1.0 ? water_surface_mean : (terrain == 2.0 ? desert_surface_mean : forest_surface_mean));
  vec2 tile_uv = UV * MAP_METRES / tile_metres;
  vec3 layer_uv = vec3(tile_uv, tile_layer(tile_uv, first_layer));
  // Tint by the soft variation of the map image. Near a border that blurry image holds the colour of the
  // neighbouring ground, which would show as a band, so large differences from the mean are ignored.
  vec3 tint = color / mean;
  float difference = max(abs(tint.r - 1.0), max(abs(tint.g - 1.0), abs(tint.b - 1.0)));
  color = texture(tile_albedo, layer_uv).rgb * mix(vec3(1.0), tint, surface_tint * (1.0 - smoothstep(0.25, 0.5, difference)));
  normal_map = texture(tile_normal, layer_uv).rgb;
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
