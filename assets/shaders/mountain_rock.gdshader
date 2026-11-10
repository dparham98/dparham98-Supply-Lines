shader_type spatial;
render_mode diffuse_burley;
// Rock for the sculpted mountains (docs/MOUNTAINS.md). Colour comes from height, slope and strata; both textures are
// projected along the three world axes so steep faces do not smear. Vertex colour: R hollows, G height from 0 to 1.
uniform sampler2D rock_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_metres = 9.0;
uniform float normal_strength = 0.9;
uniform vec3 rock_dark : source_color = vec3(0.2, 0.2, 0.2);
uniform vec3 rock_light : source_color = vec3(0.56, 0.55, 0.53);
uniform vec3 rock_warm : source_color = vec3(0.44, 0.37, 0.3);
uniform vec3 scree : source_color = vec3(0.36, 0.32, 0.25);
uniform vec3 snow : source_color = vec3(0.86, 0.88, 0.92);
uniform float snow_line = 7.8;
// Part of the map whose rock is drawn by the sculpted landscape instead (docs/LANDSCAPE_LOOKDEV.md), as world X and Z
// min and max. Set by scripts/tools/build_landscape.gd; all zero draws every mountain here.
uniform vec4 landscape_region = vec4(0.0);
varying vec3 world_position;
varying vec3 world_normal;
varying vec2 vertex_data;
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
 vertex_data = COLOR.rg;
}
vec3 axis_weights(vec3 n) {
 vec3 weights = pow(abs(n), vec3(5.0));
 return weights / (weights.x + weights.y + weights.z);
}
float sample_detail(vec3 p, vec3 weights) {
 return texture(rock_detail, p.zy).r * weights.x + texture(rock_detail, p.xz).r * weights.y + texture(rock_detail, p.xy).r * weights.z;
}
// Normal map projected along each axis, combined with the surface normal by whiteout blending.
vec3 surface_normal(vec3 p, vec3 n, vec3 weights) {
 vec3 x_map = (texture(rock_normal, p.zy).rgb * 2.0 - 1.0) * vec3(normal_strength, normal_strength, 1.0);
 vec3 y_map = (texture(rock_normal, p.xz).rgb * 2.0 - 1.0) * vec3(normal_strength, normal_strength, 1.0);
 vec3 z_map = (texture(rock_normal, p.xy).rgb * 2.0 - 1.0) * vec3(normal_strength, normal_strength, 1.0);
 x_map = vec3(x_map.xy + n.zy, abs(x_map.z) * n.x);
 y_map = vec3(y_map.xy + n.xz, abs(y_map.z) * n.y);
 z_map = vec3(z_map.xy + n.xy, abs(z_map.z) * n.z);
 return normalize(x_map.zyx * weights.x + y_map.xzy * weights.y + z_map.xyz * weights.z);
}
void fragment() {
 if (world_position.x > landscape_region.x && world_position.z > landscape_region.y && world_position.x < landscape_region.z && world_position.z < landscape_region.w) { discard; }
 vec3 n = normalize(world_normal);
 vec3 weights = axis_weights(n);
 float fine = sample_detail(world_position / detail_metres, weights);
 float broad = sample_detail(world_position / (detail_metres * 4.3) + vec3(0.37, 0.11, 0.73), weights);
 float rough_rock = fine * 0.65 + broad * 0.35;
 float flatness = smoothstep(0.5, 0.88, n.y);
 // Sedimentary bands that wander with the rock, strongest on steep faces.
 float bands = sin(world_position.y * 4.3 + broad * 9.0 + world_position.x * 0.11 + world_position.z * 0.07) * 0.5 + 0.5;
 vec3 rock = mix(rock_dark, rock_light, smoothstep(0.3, 0.72, rough_rock));
 rock = mix(rock, rock * mix(0.7, 1.15, bands), 1.0 - flatness);
 rock = mix(rock, rock_warm * (0.7 + rough_rock * 0.7), smoothstep(0.42, 0.72, broad) * 0.4);
 // Loose stone gathers on gentle ground and towards the foot.
 float low = 1.0 - smoothstep(0.02, 0.38, vertex_data.g);
 rock = mix(rock, scree * (0.75 + fine * 0.5), clamp(flatness * 0.55 + low * 0.7, 0.0, 1.0) * smoothstep(0.35, 0.7, n.y + low * 0.4));
 // Hollows stay dark, crests catch the light.
 float hollow = smoothstep(0.22, 0.72, vertex_data.r);
 rock *= mix(0.5, 1.22, hollow);
 float snow_amount = smoothstep(snow_line - 0.5, snow_line + 0.8, world_position.y + (fine - 0.5) * 1.8) * smoothstep(0.42, 0.68, n.y);
 ALBEDO = mix(rock, snow, snow_amount);
 ROUGHNESS = mix(0.93, 0.6, snow_amount);
 AO = mix(0.55, 1.0, hollow);
 AO_LIGHT_AFFECT = 0.25;
 NORMAL = normalize((VIEW_MATRIX * vec4(surface_normal(world_position / detail_metres, n, weights), 0.0)).xyz);
}
