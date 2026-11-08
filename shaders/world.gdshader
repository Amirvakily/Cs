shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// World-space triplanar PBR surface with macro variation, wall-base grime and wet puddles.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile = 3.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float rough_mul = 1.0;
uniform float normal_strength = 1.0;
uniform float macro_amount = 0.25;
uniform float grime = 0.5;
uniform float grime_height = 1.1;
uniform float wet = 0.0;
uniform float specular_amount = 0.5;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

vec3 nmap(vec2 uv) {
	vec3 t = texture(normal_tex, uv).xyz * 2.0 - 1.0;
	t.xy *= normal_strength;
	return t;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 bw = pow(abs(n), vec3(6.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 sg = step(vec3(0.0), n) * 2.0 - 1.0;
	float s = 1.0 / tile;

	// Projection frames: A = +u direction in world, V = +v direction (image down) in world.
	vec3 ax = vec3(0.0, 0.0, -sg.x); vec3 vx = vec3(0.0, -1.0, 0.0);
	vec3 az = vec3(sg.z, 0.0, 0.0);  vec3 vz = vec3(0.0, -1.0, 0.0);
	vec3 ay = vec3(1.0, 0.0, 0.0);   vec3 vy = vec3(0.0, 0.0, sg.y);
	vec2 uvx = vec2(dot(wpos, ax), dot(wpos, vx)) * s;
	vec2 uvy = vec2(dot(wpos, ay), dot(wpos, vy)) * s;
	vec2 uvz = vec2(dot(wpos, az), dot(wpos, vz)) * s;

	vec3 alb = texture(albedo_tex, uvx).rgb * bw.x + texture(albedo_tex, uvy).rgb * bw.y + texture(albedo_tex, uvz).rgb * bw.z;
	vec3 arm = texture(arm_tex, uvx).rgb * bw.x + texture(arm_tex, uvy).rgb * bw.y + texture(arm_tex, uvz).rgb * bw.z;

	vec3 tx = nmap(uvx);
	vec3 ty = nmap(uvy);
	vec3 tz = nmap(uvz);
	vec3 wx = tx.x * ax - tx.y * vx + tx.z * vec3(sg.x, 0.0, 0.0);
	vec3 wy = ty.x * ay - ty.y * vy + ty.z * vec3(0.0, sg.y, 0.0);
	vec3 wz = tz.x * az - tz.y * vz + tz.z * vec3(0.0, 0.0, sg.z);
	vec3 wn = normalize(wx * bw.x + wy * bw.y + wz * bw.z);

	// Macro variation breaks up visible tiling.
	float m1 = texture(macro_tex, (wpos.xz + vec2(wpos.y * 0.7, -wpos.y * 0.4)) * 0.035).r;
	float m2 = texture(macro_tex, wpos.xz * 0.11 + vec2(0.37, 0.71)).r;
	alb *= tint * mix(1.0 - macro_amount, 1.0 + macro_amount * 0.4, m1);
	float rough = clamp(arm.g * rough_mul, 0.04, 1.0);

	// Dirt build-up at the base of vertical surfaces.
	float vert = 1.0 - bw.y;
	float g = (1.0 - smoothstep(0.0, grime_height * (0.6 + m2 * 0.8), wpos.y)) * grime * vert;
	alb = mix(alb, alb * vec3(0.42, 0.37, 0.32), g);
	rough = mix(rough, 1.0, g * 0.5);

	// Wet streets: darker albedo, low roughness, mirror-like puddles on up-facing surfaces.
	if (wet > 0.0) {
		float up = smoothstep(0.6, 0.9, n.y);
		float puddle = smoothstep(0.5, 0.58, m2) * up;
		float damp = wet * up;
		alb *= mix(1.0, 0.55, damp * 0.6 + puddle * 0.4);
		rough = mix(rough, rough * 0.55, damp);
		rough = mix(rough, 0.04, puddle * wet);
		wn = normalize(mix(wn, n, puddle * wet));
	}

	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = arm.b;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.25;
	SPECULAR = specular_amount;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
