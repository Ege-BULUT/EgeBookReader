#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;

// Dark page for a PDF: lightness is flipped while hue is kept, then white paper becomes the theme's paper
// and black type becomes the theme's ink. A plain colour inversion would turn red headings cyan.
uniform vec4 uDst;
uniform vec3 uPaper;
uniform vec3 uInk;
uniform sampler2D uPage;

out vec4 fragColor;

void main() {
  vec2 uv = (FlutterFragCoord().xy - uDst.xy) / uDst.zw;
  vec3 c = texture(uPage, uv).rgb;
  float hi = max(c.r, max(c.g, c.b));
  float lo = min(c.r, min(c.g, c.b));
  vec3 flipped = c + (1.0 - hi - lo);
  fragColor = vec4(mix(uPaper, uInk, flipped), 1.0);
}
