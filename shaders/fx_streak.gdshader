// Camera-facing streak (cylindrical billboard) along the node's local Z axis.
// Used for tracers. The QuadMesh is 1x1; node scale.z = length, scale.x = width.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.55, 1.0);
uniform float intensity = 6.0;
instance uniform float inst_alpha = 1.0;

void vertex() {
	vec3 axis_s = (MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
	float len = length(axis_s);
	vec3 axis = axis_s / max(len, 0.0001);
	float width = length((MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - center);
	vec3 side = cross(axis, to_cam);
	float sl = length(side);
	side = sl > 0.0001 ? side / sl : vec3(1.0, 0.0, 0.0);
	vec3 wp = center + axis * VERTEX.y * len + side * VERTEX.x * width;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = UV.y; // 0 = head, 1 = tail
	float a = pow(across, 1.6) * (1.0 - smoothstep(0.15, 1.0, along)) * smoothstep(0.0, 0.05, along + 0.02);
	a *= tint.a * inst_alpha;
	ALBEDO = tint.rgb * intensity * (0.6 + 0.4 * across);
	ALPHA = a;
}
