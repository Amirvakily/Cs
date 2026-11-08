shader_type spatial;
// First-person viewmodel material.
// * Renders with its own fixed field of view (independent of the camera FOV / zoom).
// * Compresses depth into the nearest 5% of the (reverse-Z) depth range so the weapon
//   never clips into walls the player is standing against.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float vm_fov = 70.0;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform bool use_vertex_color = false;
uniform bool use_triplanar = false;
uniform float triplanar_scale = 6.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap;
uniform int rough_channel = 0; // 0 = R (grey noise), 1 = G (ARM)
uniform sampler2D metal_tex : hint_default_white, filter_linear_mipmap;
uniform bool metal_from_blue = false;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap;
uniform bool use_ao = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool use_normal = false;
uniform float normal_depth = 1.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	mat4 proj = PROJECTION_MATRIX;
	float f = 1.0 / tan(radians(vm_fov) * 0.5);
	float aspect = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
	// Keep the engine's axis signs (Vulkan clip space has Y flipped).
	proj[0][0] = sign(proj[0][0]) * f / aspect;
	proj[1][1] = sign(proj[1][1]) * f;
	POSITION = proj * view_pos;
	// Reverse-Z: near plane is depth 1. Squash the viewmodel into [0.95, 1.0].
	POSITION.z = POSITION.z * 0.05 + POSITION.w * 0.95;
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z + 0.0001);
}

vec4 tri_albedo(vec3 p, vec3 n) {
	vec3 w = tri_weights(n);
	return texture(albedo_tex, p.zy * triplanar_scale) * w.x + texture(albedo_tex, p.xz * triplanar_scale) * w.y + texture(albedo_tex, p.xy * triplanar_scale) * w.z;
}

vec4 tri_rough(vec3 p, vec3 n) {
	vec3 w = tri_weights(n);
	return texture(rough_tex, p.zy * triplanar_scale) * w.x + texture(rough_tex, p.xz * triplanar_scale) * w.y + texture(rough_tex, p.xy * triplanar_scale) * w.z;
}

void fragment() {
	vec4 a = use_triplanar ? tri_albedo(obj_pos, obj_nrm) : texture(albedo_tex, UV);
	vec3 col = albedo.rgb * a.rgb;
	if (use_vertex_color) {
		// Vertex colours are authored in sRGB.
		vec3 vc = COLOR.rgb;
		vc = mix(pow((vc + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), vc * (1.0 / 12.92), lessThan(vc, vec3(0.04045)));
		col *= vc;
	}
	ALBEDO = col;
	vec4 r = use_triplanar ? tri_rough(obj_pos, obj_nrm) : texture(rough_tex, UV);
	ROUGHNESS = roughness * (rough_channel == 1 ? r.g : r.r);
	vec4 m = texture(metal_tex, UV);
	METALLIC = metallic * (metal_from_blue ? m.b : m.r);
	if (use_ao) {
		AO = texture(ao_tex, UV).r;
		AO_LIGHT_AFFECT = 0.2;
	}
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	EMISSION = emission_color * emission_energy;
}
