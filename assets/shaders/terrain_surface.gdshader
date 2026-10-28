shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D surface_map : source_color, filter_linear_mipmap;
uniform sampler2D category_map : filter_nearest;
uniform sampler2D cleared_cells : hint_default_black, filter_nearest, repeat_disable;
void fragment() {
 vec3 color = texture(surface_map, UV).rgb;
 float terrain = round(texture(category_map, UV).r * 255.0);
 if (terrain == 1.0) {
  float wave = sin(UV.y * 900.0 + sin(UV.x * 170.0 + TIME * 0.18) * 1.4 + TIME * 0.7);
  float small = sin(UV.y * 1900.0 + UV.x * 90.0 - TIME * 0.4);
  color += vec3(0.018, 0.035, 0.04) * (wave * 0.30 + small * 0.10);
  ROUGHNESS = 0.33;
 } else { ROUGHNESS = 0.96; }
 if (texture(cleared_cells, UV).r > 0.5) { color = vec3(0.28, 0.22, 0.12); ROUGHNESS = 0.96; }
 ALBEDO = color;
}
