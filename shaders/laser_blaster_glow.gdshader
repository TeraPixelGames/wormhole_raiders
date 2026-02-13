shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Adapted from "Laser Blaster Glow" by Calfur (GodotShaders, CC0).
uniform vec4 laser_color : source_color = vec4(0.18, 1.0, 0.22, 1.0);
uniform float glow_intensity : hint_range(0.0, 50.0) = 7.0;
uniform float core_width : hint_range(0.0, 1.0) = 0.42;
uniform float core_length : hint_range(0.0, 1.0) = 0.5;
uniform float glow_feather : hint_range(0.01, 1.0) = 0.2;
uniform float halo_strength : hint_range(0.0, 2.0) = 0.45;
uniform float flicker_speed : hint_range(0.0, 40.0) = 14.0;
uniform float flicker_strength : hint_range(0.0, 0.8) = 0.14;

varying float v_fade;

void vertex() {
	v_fade = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
}

void fragment() {
	float y_dist = abs(UV.y - 0.5);
	float x_dist = abs(UV.x - 0.5);

	float core_y_mask = 1.0 - smoothstep(0.0, core_width, y_dist);
	float core_x_mask = 1.0 - smoothstep(0.0, core_length, x_dist);
	float core_mask = core_y_mask * core_x_mask;
	float glow_y_mask = 1.0 - smoothstep(core_width, min(1.0, core_width + glow_feather), y_dist);
	float glow_x_mask = 1.0 - smoothstep(core_length, min(1.0, core_length + glow_feather), x_dist);
	float halo_mask = max(glow_y_mask * glow_x_mask - core_mask, 0.0);

	float flicker = 1.0 + sin(TIME * flicker_speed + UV.x * 18.0) * flicker_strength;
	float mask = core_mask + halo_mask * halo_strength;
	float intensity = mask * glow_intensity * max(flicker, 0.0) * v_fade;
	float alpha_mask = clamp(core_mask + halo_mask * (0.55 + halo_strength * 0.2), 0.0, 1.0);

	vec3 beam = laser_color.rgb * intensity;
	ALBEDO = beam;
	EMISSION = beam;
	ALPHA = alpha_mask * laser_color.a * v_fade;
}
