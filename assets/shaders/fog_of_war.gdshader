shader_type spatial;
// Fog of war (docs/FOG_OF_WAR.md): one pass over the whole screen that darkens what lies outside the player's sight.
// It reads the scene's depth to find the ground under each pixel and looks it up in `shade`, whose alpha is 1 in
// fog and 0 in sight. With no shade set (the editor) it draws nothing.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D shade : hint_default_transparent, filter_linear, repeat_disable;
// The map's ground in world space: x and z of its first corner, then its size.
uniform vec4 map_rect = vec4(-250.0, -250.0, 500.0, 500.0);
uniform vec3 fog_color : source_color = vec3(0.03, 0.04, 0.06);
uniform float strength : hint_range(0.0, 1.0) = 0.55;
void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
void fragment() {
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec2 uv = (world.xz - map_rect.xy) / map_rect.zw;
	float fog = texture(shade, clamp(uv, vec2(0.0), vec2(1.0))).a;
	ALBEDO = fog_color;
	ALPHA = fog * strength;
}
