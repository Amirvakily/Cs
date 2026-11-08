// Additive glow shader for muzzle flashes, fire, sparks and flashes.
// billboard: 0 = mesh as-is, 1 = particle billboard (rotation from INSTANCE_CUSTOM.x), 2 = plain billboard (inst_roll).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D tex : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float intensity = 3.0;
uniform int billboard = 1;
uniform float soft_distance = 0.3;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
instance uniform float inst_alpha = 1.0;
instance uniform float inst_roll = 0.0;

void vertex() {
	if (billboard > 0) {
		float ang = billboard == 1 ? INSTANCE_CUSTOM.x : inst_roll;
		mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		mw = mw * mat4(vec4(cos(ang), -sin(ang), 0.0, 0.0), vec4(sin(ang), cos(ang), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * mw;
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec4 t = texture(tex, UV);
	float a = t.a * tint.a * COLOR.a * inst_alpha;
	if (soft_distance > 0.0) {
		float d = texture(depth_tex, SCREEN_UV).x;
		vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
		v.xyz /= v.w;
		a *= clamp((VERTEX.z - v.z) / soft_distance, 0.0, 1.0);
	}
	ALBEDO = t.rgb * tint.rgb * COLOR.rgb * intensity;
	ALPHA = a;
}
