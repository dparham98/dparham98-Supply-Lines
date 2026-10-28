shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec2 cells = vec2(8.0);
uniform vec4 tint : source_color = vec4(1.0,0.72,0.12,0.65);
varying vec2 grid_uv;
void vertex() {
	// BoxMesh uses an atlas UV layout; use local footprint coordinates instead.
	grid_uv = VERTEX.xz+vec2(0.5);
}
void fragment() {
	vec2 cell = fract(grid_uv*cells);
	vec2 edge = min(cell,vec2(1.0)-cell);
	float line = 1.0-smoothstep(0.025,0.075,min(edge.x,edge.y));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * mix(0.15,1.0,line);
}
