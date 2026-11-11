shader_type spatial;
render_mode diffuse_burley;
// Rock for the Blender kit pieces (docs/LANDSCAPE_LOOKDEV.md): the same projected rock as the sculpted ground, so a
// cliff piece set into the hill matches it. Vertex colour is the baked shading times the tint of each placement.
#include "res://assets/shaders/landscape_rock.gdshaderinc"
// Rock standing in water is dark and wet up to this height above the surface.
uniform float water_level = -0.32;
uniform float wet_height = 0.22;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}
void fragment() {
 vec3 n = normalize(world_normal);
 vec3 tint = pow(COLOR.rgb, vec3(2.2));
 float baked = clamp(max(tint.r, max(tint.g, tint.b)), 0.0, 1.0);
 vec3 rock; vec3 rock_n; float rock_shade;
 rock_surface(world_position, n, smoothstep(0.1, 0.9, baked), rock, rock_n, rock_shade);
 float wet = 1.0 - smoothstep(water_level + wet_height * 0.4, water_level + wet_height, world_position.y);
 vec3 hue = tint / max(baked, 0.05);
 // Ore and moss painted into a piece keep their own colour; plain rock takes the shared rock colour.
 float painted = clamp((max(hue.r, max(hue.g, hue.b)) - min(hue.r, min(hue.g, hue.b))) * 2.5, 0.0, 1.0);
 ALBEDO = mix(rock * mix(vec3(1.0), hue, 0.8), tint * (0.6 + dot(rock, vec3(0.33)) * 1.6), painted * 0.9) * mix(1.0, 0.5, wet);
 ROUGHNESS = mix(mix(0.92, 0.5, painted * step(hue.g, hue.b)), 0.35, wet);
 AO = rock_shade;
 AO_LIGHT_AFFECT = 0.3;
 NORMAL = normalize((VIEW_MATRIX * vec4(rock_n, 0.0)).xyz);
}
