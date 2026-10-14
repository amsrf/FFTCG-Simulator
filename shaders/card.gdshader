shader_type spatial;

// UNSHADED, DELIBERATELY. A card is artwork, not a surface: it should show the colours in the scan, not those
// colours multiplied by whatever the board's light and ambient happen to be doing. Lit, cards read washed out
// and pale beside the same card shown as a plain 2D texture in the hover preview — which is exactly how this
// was spotted.
//
// Nothing is lost by it. The meshes are still solid geometry, so tilt, overlap and stacking order are read from
// the shapes rather than from shading, and a card is the one thing on this board that is meant to be looked AT
// rather than lit. The trade is explicit: if the board ever wants cards to sit IN the light, delete this line.
render_mode unshaded;

uniform sampler2D texture_albedo : source_color;
uniform bool effect_enabled = false;
void fragment() {
    // Get the original color from the albedo texture
    vec4 original_color = texture(texture_albedo, UV);

    // If UV y coordinate is greater than 0.8, make it black
    if (effect_enabled && UV.y > 0.875) {
        ALBEDO = vec3(0.1);
    } else {
        ALBEDO = original_color.rgb;

    }
}