shader_type spatial;
render_mode diffuse_burley, cull_disabled;
// Trees and plants of the landscape kit (docs/LANDSCAPE_LOOKDEV.md). Colour and baked shading are in the vertex
// colours, multiplied by the tint of each placement. UV.x is how far a vertex sways in the wind.
uniform float wind_strength = 0.16;
uniform float wind_speed = 1.1;
uniform vec2 wind_direction = vec2(0.8, 0.6);
// Light passing through leaves on the side away from the sun.
uniform float translucency = 0.14;
// Leaf clumps: lighter and darker patches about this many metres across, and how strong they are.
uniform float mottle_metres = 0.32;
uniform float mottle_strength = 0.42;
// Bark (UV.y is 1 on trunks and limbs): furrows running up the wood, and how deep they look.
uniform float bark_furrows = 6.5;
uniform float bark_depth = 0.8;
// Cleared Forest cells, set per match by terrain_assets.gd. Whatever would hide a cleared cell from the camera is cut
// away, so a lane through the wood and the units in it can be seen past the trees in front. The same cut lets the
// sun into the lane.
uniform sampler2D cleared_cells : hint_default_black, filter_linear, repeat_disable;
varying vec3 world_position;
float hash(ivec3 p) {
 uint h = uint(p.x) * 1597334677u + uint(p.y) * 3812015801u + uint(p.z) * 2798796415u;
 h = (h ^ (h >> 15u)) * 2246822519u;
 h = (h ^ (h >> 13u)) * 3266489917u;
 h = h ^ (h >> 16u);
 return float(h) / 4294967295.0;
}
float value_noise(vec3 p) {
 ivec3 c = ivec3(floor(p));
 vec3 f = fract(p);
 f = f * f * (3.0 - 2.0 * f);
 float low = mix(mix(hash(c), hash(c + ivec3(1, 0, 0)), f.x), mix(hash(c + ivec3(0, 1, 0)), hash(c + ivec3(1, 1, 0)), f.x), f.y);
 float high = mix(mix(hash(c + ivec3(0, 0, 1)), hash(c + ivec3(1, 0, 1)), f.x), mix(hash(c + ivec3(0, 1, 1)), hash(c + ivec3(1, 1, 1)), f.x), f.y);
 return mix(low, high, f.z);
}
void vertex() {
 vec3 origin = MODEL_MATRIX[3].xyz;
 vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 // A slow gust crossing the map, and a quicker flutter that differs from plant to plant and leaf to leaf.
 float gust = sin(dot(origin.xz, wind_direction) * 0.11 + TIME * wind_speed) * 0.6 + 0.4;
 float flutter = sin(TIME * wind_speed * 2.7 + origin.x * 1.7 + origin.z * 2.3 + world.y * 1.9);
 vec3 push = vec3(wind_direction.x, 0.0, wind_direction.y) * (gust + flutter * 0.35) * wind_strength * UV.x;
 // The push is in world space; bring it into the plant's own turned and scaled space.
 world_position = world;
 VERTEX += (vec4(push, 0.0) * MODEL_MATRIX).xyz / dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz);
}
void fragment() {
 // Where the line of sight through this point meets the ground.
 vec3 sight = normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
 vec3 seen = world_position - sight * (world_position.y / min(sight.y, -0.05));
 float cleared = texture(cleared_cells, (seen.xz + 250.0) / 500.0).r;
 float grain_pick = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
 if (world_position.y > 0.9 && cleared > mix(0.3, 0.7, grain_pick)) { discard; }
 // The OBJ files hold display colours.
 float mottle = value_noise(world_position / mottle_metres) * 0.65 + value_noise(world_position / (mottle_metres * 0.37)) * 0.35;
 ALBEDO = pow(COLOR.rgb, vec3(2.2)) * (1.0 + (mottle - 0.5) * 2.0 * mottle_strength * UV.x * 2.0 * (1.0 - UV.y));
 // Bark: long furrows, broken by plates, with a paler ridge between them.
 vec3 grain = world_position * vec3(bark_furrows, 1.4, bark_furrows);
 float furrow = value_noise(grain) * 0.6 + value_noise(grain * vec3(2.3, 2.6, 2.3)) * 0.4;
 ALBEDO *= mix(1.0, mix(1.0 - bark_depth, 1.0 + bark_depth * 0.5, smoothstep(0.38, 0.62, furrow)), UV.y);
 ROUGHNESS = mix(0.88, 0.97, UV.y);
 SPECULAR = 0.25;
 BACKLIGHT = ALBEDO * translucency * (1.0 - UV.y);
 // Leaves are lit from whichever side is seen, by the normal the kit gave them.
 if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
