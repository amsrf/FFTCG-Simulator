shader_type spatial;
// No depth test: the frost lies ON the struck card, and the card's hit recoil lifts it through any plane placed just
// above its face. render_priority (ice_projectile.gd) keeps it under the crystal and its shards.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform float age = -1.0;
uniform float lifetime = 3.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
    vec2 c = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(c), hash(c + vec2(1,0)), f.x), mix(hash(c + vec2(0,1)), hash(c + vec2(1,1)), f.x), f.y);
}
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float radius = length(p);
    float grain = noise(p * 22.0) * 0.6 + noise(p * 59.0) * 0.4;
    float clouds = noise(p * 6.0) * 0.65 + noise(p * 13.0) * 0.35;
    float spread = smoothstep(0.0, 0.32, age);
    float boundary = 0.62 + (clouds - 0.5) * 0.28;
    float patch = (1.0 - smoothstep(boundary * spread - 0.12, boundary * spread, radius));
    float frost = patch * mix(0.10, 0.66, smoothstep(0.28, 0.72, clouds)) * mix(0.5, 1.0, grain);
    float angle = atan(p.y, p.x);
    float veins = pow(max(0.0, sin(angle * 17.0 + noise(p * 8.0) * 4.0)), 18.0);
    frost += veins * patch * smoothstep(0.05, 0.2, radius) * 0.17;
    frost *= 1.0 - smoothstep(lifetime - 1.0, lifetime, age);
    float wave_radius = 0.04 + 0.88 * pow(clamp(age / 0.48, 0.0, 1.0), 0.65);
    float wave = exp(-pow((radius - wave_radius) / 0.022, 2.0)) * (1.0 - smoothstep(0.06, 0.48, age));
    float flash = exp(-radius * radius * 85.0) * (1.0 - smoothstep(0.0, 0.12, age));
    ALBEDO = mix(vec3(0.45, 0.73, 0.87), vec3(0.88, 0.98, 1.0), clamp(grain * 0.6 + wave + flash, 0.0, 1.0));
    ALPHA = clamp(frost + wave * 0.85 + flash * 0.7, 0.0, 0.9) * step(0.0, age);
}
