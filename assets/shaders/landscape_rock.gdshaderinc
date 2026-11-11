// Rock shared by the sculpted landscape ground and the Blender kit pieces (docs/LANDSCAPE_LOOKDEV.md), so a cliff
// piece set into the mountain edge matches the rock around it. Both textures are projected along the three world
// axes, which also keeps the grain the same size whatever a piece's scale or turn.
uniform sampler2D rock_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_detail_metres = 4.5;
uniform float rock_normal_strength = 1.5;
uniform vec3 rock_dark : source_color = vec3(0.17, 0.155, 0.145);
uniform vec3 rock_light : source_color = vec3(0.5, 0.47, 0.42);
uniform vec3 rock_warm : source_color = vec3(0.43, 0.33, 0.25);
uniform vec3 rock_dust : source_color = vec3(0.5, 0.46, 0.38);
// Snow lies on level rock above this height, in metres. Only the tallest rock reaches it.
uniform float snow_line = 8.1;
uniform vec3 snow_color : source_color = vec3(0.86, 0.89, 0.94);
// Strength of the sedimentary bands on steep faces.
uniform float strata_strength = 0.55;

vec3 rock_axis_weights(vec3 n) {
 vec3 weights = pow(abs(n), vec3(5.0));
 return weights / (weights.x + weights.y + weights.z);
}
float rock_sample(vec3 p, vec3 weights) {
 return texture(rock_detail, p.zy).r * weights.x + texture(rock_detail, p.xz).r * weights.y + texture(rock_detail, p.xy).r * weights.z;
}
// Normal map projected along each axis, combined with the surface normal by whiteout blending.
vec3 rock_normal_at(vec3 p, vec3 n, vec3 weights) {
 vec3 x_map = (texture(rock_normal, p.zy).rgb * 2.0 - 1.0) * vec3(rock_normal_strength, rock_normal_strength, 1.0);
 vec3 y_map = (texture(rock_normal, p.xz).rgb * 2.0 - 1.0) * vec3(rock_normal_strength, rock_normal_strength, 1.0);
 vec3 z_map = (texture(rock_normal, p.xy).rgb * 2.0 - 1.0) * vec3(rock_normal_strength, rock_normal_strength, 1.0);
 x_map = vec3(x_map.xy + n.zy, abs(x_map.z) * n.x);
 y_map = vec3(y_map.xy + n.xz, abs(y_map.z) * n.y);
 z_map = vec3(z_map.xy + n.xy, abs(z_map.z) * n.z);
 return normalize(x_map.zyx * weights.x + y_map.xzy * weights.y + z_map.xyz * weights.z);
}
// hollow: 0 in crevices, 1 on crests. Returns colour, world normal and ambient shading.
void rock_surface(vec3 p, vec3 n, float hollow, out vec3 albedo, out vec3 normal, out float shade) {
 vec3 weights = rock_axis_weights(n);
 float fine = rock_sample(p / rock_detail_metres, weights);
 float broad = rock_sample(p / (rock_detail_metres * 4.3) + vec3(0.37, 0.11, 0.73), weights);
 float grain = fine * 0.65 + broad * 0.35;
 float flatness = smoothstep(0.55, 0.9, n.y);
 // Level beds, tilted a little and bent by the broad pattern so they never run ruler straight.
 float bed = p.y * 2.6 + broad * 2.4 + p.x * 0.05 + p.z * 0.04;
 float bands = smoothstep(0.25, 0.75, sin(bed) * 0.5 + 0.5) * 0.6 + smoothstep(0.3, 0.7, sin(bed * 3.7 + 1.3) * 0.5 + 0.5) * 0.4;
 vec3 rock = mix(rock_dark, rock_light, smoothstep(0.28, 0.74, grain));
 rock = mix(rock, rock_warm * (0.65 + grain * 0.75), smoothstep(0.42, 0.7, broad) * 0.45);
 rock *= mix(1.0, mix(0.62, 1.12, bands), strata_strength * (1.0 - flatness));
 // Dust and grit settle on level rock.
 rock = mix(rock, rock_dust * (0.7 + fine * 0.55), flatness * smoothstep(0.35, 0.6, broad) * 0.55);
 float open = smoothstep(0.2, 0.75, hollow);
 albedo = rock * mix(0.76, 1.14, open);
 // Snow: thick on the tops, dusted into the ledges just below the line, none on steep faces.
 float snow = smoothstep(snow_line - 0.4, snow_line + 0.7, p.y + (fine - 0.5) * 2.4 + (broad - 0.5) * 2.0) * smoothstep(0.5, 0.78, n.y);
 albedo = mix(albedo, snow_color * mix(0.82, 1.0, open), snow);
 normal = rock_normal_at(p / rock_detail_metres, n, weights);
 shade = mix(0.66, 1.0, open);
}
