shader_type spatial;
render_mode diffuse_burley;
// Ground of the sculpted landscape (docs/LANDSCAPE_LOOKDEV.md). Open grass and desert are drawn exactly as in
// terrain_surface.gdshader, so the two meet without a seam at the region edge. On top of that the shore, the forest
// floor, ore ground, the mountain foot and the rock itself are blended in from the landscape fields, which
// scripts/tools/build_landscape.gd makes from the map cells: R shore, G rock, B forest, A ore.
#include "res://assets/shaders/landscape_rock.gdshaderinc"
uniform sampler2D surface_map : source_color, filter_linear_mipmap;
uniform sampler2D cleared_cells : hint_default_black, filter_linear, repeat_disable;
uniform sampler2DArray tile_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tile_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_blend : filter_linear, repeat_disable;
uniform sampler2D fields : filter_linear, repeat_disable;
// These match terrain_surface.gdshader. Change both together.
uniform float tile_metres = 4.0;
uniform float feature_share = 0.2;
uniform float surface_tint = 1.0;
uniform vec3 grass_surface_mean = vec3(0.097, 0.161, 0.041);
uniform vec3 desert_surface_mean = vec3(0.586, 0.399, 0.137);
uniform float border_wander = 0.65;
uniform float border_softness = 0.28;
uniform float dry_margin = 6.0;
uniform float dry_strength = 0.55;
uniform float macro_strength = 1.0;
uniform float breakup_strength = 0.55;
uniform float grass_relief = 0.5;
uniform float desert_relief = 1.0;
// Landscape layers, as tints of the desert tile so they carry its grain.
uniform vec3 beach_tint = vec3(0.92, 1.12, 1.55);
uniform vec3 mud_tint = vec3(0.4, 0.36, 0.32);
uniform vec3 litter_tint = vec3(0.2, 0.19, 0.11);
uniform vec3 cleared_tint = vec3(0.38, 0.31, 0.22);
uniform vec3 ore_tint = vec3(0.36, 0.2, 0.15);
// Metres of beach above the waterline, and of loose stone out from the rock.
uniform float beach_width = 1.7;
uniform float scree_width = 2.2;
// Meadow: clumps of taller, darker grass and worn bare patches. scripts/tools/landscape_baker.gd reads the same
// noise to stand tall grass on the clumps, so change the numbers in both.
uniform vec3 clump_tint = vec3(0.66, 0.84, 0.6);
uniform vec3 bare_tint = vec3(0.4, 0.36, 0.28);
// Colour the bed takes far under water.
uniform vec3 deep_bed : source_color = vec3(0.03, 0.12, 0.16);
const float MAP_METRES = 500.0;
const float BLEND_RANGE = 8.0;
const float FIELD_RANGE = 8.0;
varying vec3 world_position;
varying vec3 world_normal;
varying vec3 vertex_data;
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
 vertex_data = COLOR.rgb;
}
float tile_layer(vec2 tile_uv, float first_layer) {
 float pick = fract(sin(dot(floor(tile_uv), vec2(127.1, 311.7))) * 43758.5453);
 if (pick < feature_share) { return first_layer + 2.0 + floor(pick / feature_share * 2.0); }
 return first_layer + floor((pick - feature_share) / (1.0 - feature_share) * 2.0);
}
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
void ground_set(vec2 tile_uv, float first_layer, vec3 map_color, vec3 mean, float map_tint, float breakup, out vec3 albedo, out vec3 normal_rgb) {
 vec3 layer_uv = vec3(tile_uv, tile_layer(tile_uv, first_layer));
 vec3 tint = map_color / mean;
 float difference = max(abs(tint.r - 1.0), max(abs(tint.g - 1.0), abs(tint.b - 1.0)));
 albedo = texture(tile_albedo, layer_uv).rgb * mix(vec3(1.0), tint, map_tint * (1.0 - smoothstep(0.25, 0.5, difference)));
 normal_rgb = texture(tile_normal, layer_uv).rgb;
 vec3 large = texture(tile_albedo, vec3(tile_uv.yx * 0.293 + vec2(0.37, 0.11), first_layer)).rgb;
 vec3 average = textureLod(tile_albedo, vec3(0.5, 0.5, first_layer), 9.0).rgb;
 albedo *= mix(vec3(1.0), clamp(large / max(average, vec3(0.01)), vec3(0.5), vec3(1.6)), breakup);
}
void fragment() {
 vec3 map_color = texture(surface_map, UV).rgb;
 vec2 tile_uv = UV * MAP_METRES / tile_metres;
 vec2 metres = UV * MAP_METRES;
 // Open ground, as in terrain_surface.gdshader.
 float signed_metres = (texture(ground_blend, UV).r - 0.5) * 2.0 * BLEND_RANGE;
 float map_tint = surface_tint * smoothstep(1.5, 4.0, abs(signed_metres));
 vec3 grass; vec3 grass_normal; vec3 desert; vec3 desert_normal;
 ground_set(tile_uv, 0.0, map_color, grass_surface_mean, map_tint, breakup_strength, grass, grass_normal);
 ground_set(tile_uv, 4.0, map_color, desert_surface_mean, map_tint, breakup_strength, desert, desert_normal);
 // The desert tile without any tint: the grain for sand, mud, litter, ore ground and scree.
 vec3 earth;
 ground_set(tile_uv, 4.0, desert_surface_mean, desert_surface_mean, 0.0, breakup_strength, earth, desert_normal);
 float wander = (layered_noise(metres * 0.32, 4) - 0.5) * 4.0 * border_wander;
 float softness = max(border_softness, fwidth(signed_metres) * 1.5);
 float into_desert = smoothstep(-softness, softness, signed_metres + wander);
 float broad = layered_noise(metres / 64.0 + vec2(3.1, 7.7), 3);
 float patches = layered_noise(metres / 17.0 + vec2(11.9, 2.3), 3);
 vec3 grass_shift = mix(vec3(0.78, 0.84, 0.72), vec3(1.2, 1.14, 0.92), smoothstep(0.28, 0.72, broad));
 grass *= mix(vec3(1.0), grass_shift, macro_strength);
 float dry = max(smoothstep(0.56, 0.74, patches) * 0.45, (1.0 - smoothstep(0.0, dry_margin, -signed_metres + wander)) * dry_strength);
 grass = mix(grass, grass * vec3(1.55, 1.18, 0.62), dry * macro_strength);
 vec3 desert_shift = mix(vec3(0.84, 0.79, 0.74), vec3(1.12, 1.08, 1.02), smoothstep(0.26, 0.74, broad));
 desert *= mix(vec3(1.0), desert_shift, macro_strength);
 desert *= mix(vec3(1.0), vec3(0.86, 0.82, 0.76), (1.0 - smoothstep(0.34, 0.6, patches)) * 0.7 * macro_strength);
 vec3 color = mix(grass, desert, into_desert);
 vec3 normal_map = mix(grass_normal, desert_normal, into_desert);
 float relief = mix(grass_relief, desert_relief, into_desert);
 vec2 relief_uv = metres / 22.0;
 float height = layered_noise(relief_uv, 3);
 vec2 slope = vec2(layered_noise(relief_uv + vec2(0.06, 0.0), 3) - height, layered_noise(relief_uv + vec2(0.0, 0.06), 3) - height) / 0.06;
 vec2 bent = normal_map.xy - 0.5 - slope * 0.1 * relief;
 bent *= min(1.0, 0.42 / max(length(bent), 0.001));
 color *= 1.0 + (height - 0.5) * 0.12 * relief;
 float roughness = 0.96;

 // Landscape layers.
 vec4 field = texture(fields, UV2);
 float shore = (field.r - 0.5) * 2.0 * FIELD_RANGE;
 float rock_edge = (field.g - 0.5) * 2.0 * FIELD_RANGE;
 float fine = layered_noise(metres * 1.3, 3) - 0.5;
 float coarse = layered_noise(metres * 0.37 + vec2(5.3, 1.9), 3) - 0.5;
 vec3 earth_average = textureLod(tile_albedo, vec3(0.5, 0.5, 4.0), 9.0).rgb;
 float grain_light = dot(earth, vec3(0.3, 0.5, 0.2)) / max(dot(earth_average, vec3(0.3, 0.5, 0.2)), 0.01);
 // Meadow, only inside the region (vertex colour B is 0 at its edge, where this ground meets the flat map's).
 float meadow = (1.0 - into_desert) * vertex_data.b;
 float clump = smoothstep(0.58, 0.7, layered_noise(metres / 9.0 + vec2(41.0, 7.0), 3)) * meadow;
 color *= mix(vec3(1.0), clump_tint * (0.9 + fine * 0.5), clump);
 float bare = smoothstep(0.72, 0.82, layered_noise(metres / 6.0 + vec2(3.0, 77.0), 3) + fine * 0.12) * meadow;
 color = mix(color, earth * bare_tint * (0.85 + fine * 0.6), bare * 0.7);
 // Forest floor: needle and leaf litter with moss showing through, thinning out to grass at the edge.
 float litter = smoothstep(0.3, 0.62, field.b + coarse * 0.5 + fine * 0.2);
 vec3 litter_color = mix(earth * litter_tint, grass * vec3(0.42, 0.62, 0.36), smoothstep(-0.22, 0.12, coarse + fine * 0.6) * 0.85);
 color = mix(color, litter_color, litter * 0.9);
 // A cleared cell is churned earth, soft at its edges so it sits in the litter around it.
 float cleared = smoothstep(0.3, 0.7, texture(cleared_cells, UV).r + fine * 0.35);
 color = mix(color, earth * cleared_tint * (0.85 + fine * 0.5), cleared);
 // Ore ground.
 float ore = smoothstep(0.3, 0.68, field.a + fine * 0.3);
 color = mix(color, earth * ore_tint, ore * 0.92);
 // Loose stone out from the rock.
 float scree = smoothstep(-scree_width, -0.1, rock_edge + coarse * 2.2 + fine * 1.6);
 vec3 scree_color = rock_dust * grain_light * (0.7 + fine * 0.9);
 color = mix(color, scree_color, scree * 0.85);
 // Beach, then wet ground at the waterline, then the bed fading into the deep.
 float beach = smoothstep(-beach_width, -beach_width * 0.45, shore + coarse * 1.3 + fine * 0.5);
 vec3 sand = earth * beach_tint * mix(vec3(0.74, 0.72, 0.66), vec3(1.0), into_desert);
 color = mix(color, sand, beach);
 float wet = smoothstep(-0.5, -0.05, shore + fine * 0.3);
 color = mix(color, earth * mud_tint, wet * 0.8);
 roughness = mix(roughness, 0.42, wet * (1.0 - smoothstep(0.0, 0.4, shore)));
 float under = smoothstep(0.0, 3.5, shore);
 color = mix(color, deep_bed, under * 0.85);
 bent *= 1.0 - max(beach * 0.5, under);

 // Rock: everything inside the mountain edge and anything steep.
 vec3 n = normalize(world_normal);
 // The tile normal in the same frame the flat ground plane uses: +X across, -Z up the image.
 vec2 tilt = bent * 2.0;
 vec3 across = normalize(vec3(1.0, 0.0, 0.0) - n * n.x);
 vec3 ground_normal = normalize(across * tilt.x + cross(n, across) * tilt.y + n * sqrt(max(1.0 - dot(tilt, tilt), 0.0)));
 float rockiness = max(smoothstep(-0.25, 0.3, rock_edge + fine * 0.5), smoothstep(0.35, 0.6, 1.0 - n.y));
 rockiness *= 1.0 - smoothstep(0.2, 1.2, shore);
 vec3 rock; vec3 rock_n; float rock_shade;
 rock_surface(world_position, n, vertex_data.r, rock, rock_n, rock_shade);
 ALBEDO = mix(color, rock, rockiness);
 ROUGHNESS = mix(roughness, 0.92, rockiness);
 AO = mix(1.0, rock_shade, rockiness);
 AO_LIGHT_AFFECT = 0.3;
 NORMAL = normalize((VIEW_MATRIX * vec4(normalize(mix(ground_normal, rock_n, rockiness)), 0.0)).xyz);
}
