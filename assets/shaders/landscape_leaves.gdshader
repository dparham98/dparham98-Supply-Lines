shader_type spatial;
render_mode diffuse_burley, cull_disabled;
// Leaf and needle sprays of the landscape trees (docs/LANDSCAPE_LOOKDEV.md): flat cards cut out by the leaf atlas,
// which Blender/Terrain/build/build_landscape_kit.py draws. Atlas R is how light a leaf is, A the cut-out. Colour is
// in the vertex colours, multiplied by the tint of each placement.
uniform sampler2D leaf_atlas : filter_linear_mipmap_anisotropic, repeat_disable;
uniform float cutout = 0.42;
// Cleared Forest cells, set per match by terrain_assets.gd. Whatever would hide a cleared cell from the camera is cut
// away, so a lane through the wood and the units in it can be seen past the trees in front. The same cut lets the
// sun into the lane.
uniform sampler2D cleared_cells : hint_default_black, filter_linear, repeat_disable;
varying vec3 reveal_position;
uniform float wind_strength = 0.2;
uniform float wind_speed = 1.1;
uniform vec2 wind_direction = vec2(0.8, 0.6);
// Height above the tree's foot at which the sway is full, in the tree's own metres.
uniform float sway_height = 7.0;
// Light passing through leaves on the side away from the sun.
uniform float translucency = 0.3;
void vertex() {
 vec3 origin = MODEL_MATRIX[3].xyz;
 vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 reveal_position = world;
 float weight = clamp(VERTEX.y / sway_height, 0.0, 1.0);
 float gust = sin(dot(origin.xz, wind_direction) * 0.11 + TIME * wind_speed) * 0.6 + 0.4;
 float flutter = sin(TIME * wind_speed * 2.7 + world.x * 1.7 + world.z * 2.3 + world.y * 1.9);
 vec3 push = vec3(wind_direction.x, 0.0, wind_direction.y) * (gust * weight * weight + flutter * 0.2 * weight) * wind_strength;
 VERTEX += (vec4(push, 0.0) * MODEL_MATRIX).xyz / dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz);
}
void fragment() {
 // Where the line of sight through this point meets the ground.
 vec3 sight = normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
 vec3 seen = reveal_position - sight * (reveal_position.y / min(sight.y, -0.05));
 float cleared = texture(cleared_cells, (seen.xz + 250.0) / 500.0).r;
 float grain_pick = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
 if (reveal_position.y > 0.9 && cleared > mix(0.3, 0.7, grain_pick)) { discard; }
 vec4 leaf = texture(leaf_atlas, UV);
 // The OBJ files hold display colours.
 ALBEDO = pow(COLOR.rgb, vec3(2.2)) * mix(0.45, 1.3, leaf.r);
 ALPHA = leaf.a;
 ALPHA_SCISSOR_THRESHOLD = cutout;
 ROUGHNESS = 0.82;
 SPECULAR = 0.3;
 BACKLIGHT = ALBEDO * translucency;
 // Lit by the normal the kit gave the spray, whichever side is seen.
 if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
