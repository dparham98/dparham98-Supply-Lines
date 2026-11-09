// Rolls the Tank's running gear on the imported meshes (docs/TANK_TRACKS.md).
// Track_Links_L/R hold 37 identical links, 24 vertices each, in order around the loop: each link
// slides rigidly toward the pose of the link ahead of it, so `roll` from 0 to 1 is one link pitch
// and the loop repeats seamlessly. Road wheels and return rollers are single meshes holding a row
// of wheels along Z; with wheel_spacing set, each turns by `roll` radians about its own centre.
// At roll 0 every vertex is exactly where the model authored it.
shader_type spatial;
render_mode cull_disabled; // the model is authored double-sided

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_rough_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D emission_texture : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wheel_spacing = 0.0; // 0 = track links
instance uniform float roll = 0.0;

const int LINK_COUNT = 37;
const int LINK_VERTICES = 24;
// Each link's rest centre (mesh X, Z) and rotation about mesh Y.
const vec3 LINKS[37] = {
	vec3(-3.08732, -0.15163, -2.83565),
	vec3(-3.56655, -0.30383, -2.82925),
	vec3(-4.01460, -0.50915, -2.52789),
	vec3(-4.24716, -0.89997, -1.66694),
	vec3(-4.09128, -1.32424, -0.77667),
	vec3(-3.66059, -1.51017, -0.05716),
	vec3(-3.15850, -1.52151, -0.00354),
	vec3(-2.65569, -1.52286, -0.00265),
	vec3(-2.15287, -1.52421, -0.00177),
	vec3(-1.65005, -1.52556, -0.00088),
	vec3(-1.14724, -1.52692, 0.00000),
	vec3(-0.64442, -1.52827, 0.00088),
	vec3(-0.14160, -1.52962, 0.00177),
	vec3(0.36121, -1.53097, 0.00265),
	vec3(0.86403, -1.53232, 0.00354),
	vec3(1.36684, -1.53367, 0.00442),
	vec3(1.86966, -1.53503, 0.00531),
	vec3(2.37248, -1.53638, 0.00619),
	vec3(2.87529, -1.53773, 0.00707),
	vec3(3.37811, -1.53908, 0.00796),
	vec3(3.86791, -1.48127, 0.29936),
	vec3(4.21701, -1.18610, 1.13992),
	vec3(4.22441, -0.72914, 1.98285),
	vec3(3.88715, -0.40787, 2.74045),
	vec3(3.41443, -0.24430, 2.85893),
	vec3(2.92957, -0.11555, 2.93318),
	vec3(2.43264, -0.07000, 3.14038),
	vec3(1.92982, -0.07000, 3.14157),
	vec3(1.42701, -0.07000, -3.14042),
	vec3(0.92419, -0.07000, -3.13922),
	vec3(0.42137, -0.07000, -3.13802),
	vec3(-0.08145, -0.07000, -3.13683),
	vec3(-0.58427, -0.07000, -3.13563),
	vec3(-1.08708, -0.07000, -3.13443),
	vec3(-1.58990, -0.07000, -3.13324),
	vec3(-2.09272, -0.07000, -3.13204),
	vec3(-2.59530, -0.07362, -3.11228)
};

vec2 turn(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x*c-v.y*s, v.x*s+v.y*c);
}

void vertex() {
	if (wheel_spacing > 0.0) {
		float centre = round(VERTEX.z/wheel_spacing)*wheel_spacing;
		vec2 p = turn(vec2(VERTEX.z-centre, VERTEX.y), -roll);
		VERTEX.z = p.x+centre;
		VERTEX.y = p.y;
		vec2 n = turn(NORMAL.zy, -roll);
		NORMAL.z = n.x;
		NORMAL.y = n.y;
	} else {
		int link = VERTEX_ID/LINK_VERTICES;
		vec3 here = LINKS[link];
		vec3 ahead = LINKS[(link+LINK_COUNT-1)%LINK_COUNT];
		float delta = mod(ahead.z-here.z+PI, TAU)-PI;
		vec2 p = turn(VERTEX.xz-here.xy, delta*roll)+mix(here.xy, ahead.xy, roll);
		VERTEX.x = p.x;
		VERTEX.z = p.y;
		vec2 n = turn(NORMAL.xz, delta*roll);
		NORMAL.x = n.x;
		NORMAL.z = n.y;
	}
}

void fragment() {
	vec4 mr = texture(metal_rough_texture, UV);
	ALBEDO = texture(albedo_texture, UV).rgb;
	METALLIC = mr.b;
	ROUGHNESS = mr.g;
	EMISSION = texture(emission_texture, UV).rgb*2.5; // the glTF emissive strength
}
