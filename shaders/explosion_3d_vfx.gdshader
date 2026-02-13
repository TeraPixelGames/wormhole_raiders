shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Based on the GodotShaders "3D Explosion VFX" approach:
// camera-facing quads + depth-aware soft blending.
uniform vec4 enemy_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform vec4 player_color : source_color = vec4(1.0, 0.15, 0.15, 1.0);
uniform float glow_strength : hint_range(0.0, 20.0) = 6.5;
uniform float smoke_strength : hint_range(0.0, 2.0) = 0.65;
uniform float soft_limit : hint_range(0.01, 2.0) = 0.22;
uniform float blend_scale : hint_range(0.0, 1.0) = 0.12;

uniform sampler2D depth_texture : source_color, hint_depth_texture;

varying float v_progress;
varying float v_kind;
varying float v_intensity;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.11369, 0.13787));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	mat4 mat_world = mat4(
		normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2]),
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	v_progress = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
	v_kind = INSTANCE_CUSTOM.g;
	v_intensity = max(INSTANCE_CUSTOM.b, 0.1);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float p = v_progress;
	float seed = hash12(uv * 8.0 + vec2(TIME * 0.8, p * 12.0));

	float core = 1.0 - smoothstep(0.10 + p * 0.1, 0.48 + p * 0.38, r);
	float ring_center = 0.24 + p * 0.52;
	float ring = (1.0 - smoothstep(ring_center, ring_center + 0.07, r)) * smoothstep(ring_center - 0.10, ring_center - 0.02, r);
	float smoke = (1.0 - smoothstep(0.28, 1.0, r)) * (1.0 - p) * (0.65 + seed * 0.35);

	vec3 base_color = mix(enemy_color.rgb, player_color.rgb, step(0.5, v_kind));
	vec3 col = base_color * (core * 0.95 + ring * 1.1 + smoke * smoke_strength * 0.35);
	vec3 emissive = base_color * (core * 1.7 + ring * 2.4 + smoke * smoke_strength) * glow_strength * v_intensity;
	float alpha_raw = clamp((core * 0.8 + ring * 0.75 + smoke * 0.4) * (1.0 - p), 0.0, 1.0);

	// Depth softening (from source shader technique).
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	float scene_z = upos.z / upos.w;
	vec4 zpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z * 2.0 - 1.0, 1.0);
	float frag_z = zpos.z / zpos.w;
	float fade_limit = soft_limit + blend_scale * (1.0 - p);
	float soft = clamp(abs(frag_z - scene_z) / max(fade_limit, 0.001), 0.0, 1.0);
	soft = max(soft, 0.22);

	ALBEDO = col;
	EMISSION = emissive;
	ALPHA = alpha_raw * soft;
}
