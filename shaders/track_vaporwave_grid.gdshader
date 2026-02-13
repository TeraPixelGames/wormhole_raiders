shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 background_color : source_color = vec4(0.0, 0.08, 0.16, 1.0);
uniform vec4 grid_color : source_color = vec4(1.0, 0.45, 0.95, 1.0);
uniform vec2 grid_scale = vec2(10.0, 26.0);
uniform float line_width_u : hint_range(0.001, 0.2) = 0.02;
uniform float line_width_v : hint_range(0.001, 0.2) = 0.05;
uniform float glow_width_u : hint_range(0.002, 0.4) = 0.08;
uniform float glow_width_v : hint_range(0.002, 0.4) = 0.12;
uniform float glow_strength : hint_range(0.0, 2.0) = 1.0;
uniform float section_world_span : hint_range(1.0, 100.0) = 22.0;
uniform float longitudinal_tiling : hint_range(0.01, 1.0) = 0.08;
uniform float seam_shift : hint_range(0.0, 1.0) = 0.37;
uniform float flow_visual_strength : hint_range(0.0, 1.5) = 0.0;
uniform float pulse_angle : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_z = 0.0;
uniform float pulse_strength : hint_range(0.0, 2.0) = 0.0;
uniform float pulse_angle_width : hint_range(0.01, 0.5) = 0.08;
uniform float pulse_z_width : hint_range(1.0, 40.0) = 12.0;
uniform vec4 flash_tint : source_color = vec4(1.0, 0.95, 0.5, 1.0);
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;
uniform float desat_amount : hint_range(0.0, 1.0) = 0.0;

// Driven by VFXSystem
uniform float scroll_speed : hint_range(0.0, 40.0) = 12.0;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float difficulty : hint_range(0.0, 5.0) = 0.0;

varying float v_section_start;
varying vec2 v_ring;

float line_mask(float coord, float width) {
    float f = fract(coord);
    float p = min(f, 1.0 - f);
    return 1.0 - smoothstep(width, width * 1.4, p);
}

float cyclic_dist(float a, float b) {
    return abs(fract(a - b + 0.5) - 0.5);
}

void vertex() {
    // Geometry bending is handled by TunnelSystem section transforms.
    v_section_start = INSTANCE_CUSTOM.r;
    v_ring = normalize(vec2(VERTEX.x, VERTEX.z));
}

void fragment() {
    float around = fract(atan(v_ring.y, v_ring.x) / 6.28318530718 + 0.5 + seam_shift);
    float longitudinal = v_section_start + UV.y * section_world_span;

    vec2 uv = vec2(around * grid_scale.x, longitudinal * longitudinal_tiling * grid_scale.y);
    uv.y += TIME * (0.18 + scroll_speed * 0.03);
    float hard_x = line_mask(uv.x, line_width_u);
    float hard_y = line_mask(uv.y, line_width_v);
    float glow_x = line_mask(uv.x, glow_width_u);
    float glow_y = line_mask(uv.y, glow_width_v);

    // Sum both axes so the ring lines remain visible, not just radial spokes.
    float hard_grid = clamp(hard_x + hard_y, 0.0, 1.4);
    float glow_grid = clamp(glow_x + glow_y, 0.0, 1.4) * glow_strength;
    float grid_val = clamp(glow_grid + hard_grid, 0.0, 1.4);
    float pulse_a = 1.0 - smoothstep(0.0, pulse_angle_width, cyclic_dist(around, pulse_angle));
    float pulse_l = 1.0 - smoothstep(0.0, pulse_z_width, abs(longitudinal - pulse_z));
    float pulse_val = pulse_a * pulse_l * pulse_strength;
    float flow = 1.0 - smoothstep(0.78, 0.98, abs(sin(longitudinal * 0.12 + TIME * 2.2 + around * 15.0)));

    vec3 col = mix(background_color.rgb, grid_color.rgb, grid_val);
    col += grid_color.rgb * pulse_val * 0.65;
    col += vec3(0.35, 0.75, 1.0) * flow * flow_visual_strength * 0.45;
    col = mix(col, flash_tint.rgb, flash_strength);
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(lum), desat_amount);
    col *= intensity;

    ALBEDO = col;
    EMISSION = col;
}
