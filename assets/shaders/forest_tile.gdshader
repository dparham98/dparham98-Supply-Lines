shader_type spatial;
render_mode diffuse_burley;
// Forest tiles (scenes/terrain/forest_tile_*.tscn): vertex colours, a tint and, on the textured tiles, the forest
// atlas, drawn as the StandardMaterial3D they replace. Over coal the leaves thin out so the seam shows through.
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
// The painted tiles hold their vertex colours in sRGB.
uniform bool vertex_color_is_srgb = false;
uniform float roughness = 0.94;
// The match's clearing mask, set per match by terrain_assets.gd. Its green channel marks coal seams and the cells
// beside them (scripts/terrain/terrain_grid.gd).
uniform sampler2D cleared_cells : hint_default_black, filter_linear, repeat_disable;
// Share of the leaves left out over the middle of a seam, and the height above the ground below which the trunks
// and undergrowth stay whole.
uniform float seam_thinning = 0.85;
uniform float clump_metres = 0.7;
uniform float trunk_height = 1.1;
varying vec3 world_position;
float seam_hash(ivec3 p) {
 uint h = uint(p.x) * 1597334677u + uint(p.y) * 3812015801u + uint(p.z) * 2798796415u;
 h = (h ^ (h >> 15u)) * 2246822519u;
 h = (h ^ (h >> 13u)) * 3266489917u;
 h = h ^ (h >> 16u);
 return float(h) / 4294967295.0;
}
// Over a seam whole clumps of leaves, about clump_metres across, are left out rather than scattered pixels.
float seam_clumps(vec3 p) {
 ivec3 c = ivec3(floor(p));
 vec3 f = fract(p);
 f = f * f * (3.0 - 2.0 * f);
 float low = mix(mix(seam_hash(c), seam_hash(c + ivec3(1, 0, 0)), f.x), mix(seam_hash(c + ivec3(0, 1, 0)), seam_hash(c + ivec3(1, 1, 0)), f.x), f.y);
 float high = mix(mix(seam_hash(c + ivec3(0, 0, 1)), seam_hash(c + ivec3(1, 0, 1)), f.x), mix(seam_hash(c + ivec3(0, 1, 1)), seam_hash(c + ivec3(1, 1, 1)), f.x), f.y);
 return smoothstep(0.2, 0.8, mix(low, high, f.z));
}
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 if (vertex_color_is_srgb) {
  COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
 }
}
void fragment() {
 // Where the line of sight through this point meets the ground: leaves in front of a seam, seen from the camera,
 // are the ones that hide it.
 vec3 sight = normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
 vec3 seen = world_position - sight * (world_position.y / min(sight.y, -0.05));
 float seam = texture(cleared_cells, (seen.xz + 250.0) / 500.0).g;
 if (world_position.y > trunk_height && seam * seam_thinning > seam_clumps(world_position / clump_metres)) { discard; }
 ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb * COLOR.rgb;
 ROUGHNESS = roughness;
}
