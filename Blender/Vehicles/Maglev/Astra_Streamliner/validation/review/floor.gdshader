shader_type spatial;
render_mode diffuse_burley;

varying vec2 ground_point;
void vertex() {
    ground_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
    vec2 p = ground_point / 4.0;
    vec2 px = max(fwidth(p), vec2(0.00001));
    vec2 dist_to_seam = abs(fract(p + 0.5) - 0.5) / px;
    float seam = 1.0 - smoothstep(0.25, 1.15, min(dist_to_seam.x, dist_to_seam.y));
    ALBEDO = mix(vec3(0.243, 0.282, 0.289), vec3(0.19, 0.224, 0.232), seam);
    ROUGHNESS = 0.93;
}
