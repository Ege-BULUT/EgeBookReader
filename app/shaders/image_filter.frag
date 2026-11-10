#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;

// Filters for a picture in a book. Upscaling is a Catmull-Rom resample followed by contrast-adaptive
// sharpening: fast enough for any GPU, and it invents no detail, so it cannot damage the picture.
uniform vec4 uDst;
uniform vec4 uSrc;
uniform vec2 uTexel;
uniform float uSaturation;
uniform float uContrast;
uniform float uSharpen;
uniform float uBicubic;
uniform sampler2D uImage;

out vec4 fragColor;

vec3 at(vec2 uv) { return texture(uImage, uv).rgb; }

vec3 catmullRom(vec2 uv) {
  vec2 p = uv / uTexel - 0.5;
  vec2 f = fract(p);
  vec2 base = (floor(p) + 0.5) * uTexel;
  vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
  vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
  vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
  vec2 w3 = f * f * (-0.5 + 0.5 * f);
  vec2 w12 = w1 + w2;
  vec2 t0 = base - uTexel;
  vec2 t12 = base + uTexel * w2 / w12;
  vec2 t3 = base + 2.0 * uTexel;
  vec3 c = at(vec2(t0.x, t0.y)) * w0.x * w0.y + at(vec2(t12.x, t0.y)) * w12.x * w0.y + at(vec2(t3.x, t0.y)) * w3.x * w0.y
         + at(vec2(t0.x, t12.y)) * w0.x * w12.y + at(vec2(t12.x, t12.y)) * w12.x * w12.y + at(vec2(t3.x, t12.y)) * w3.x * w12.y
         + at(vec2(t0.x, t3.y)) * w0.x * w3.y + at(vec2(t12.x, t3.y)) * w12.x * w3.y + at(vec2(t3.x, t3.y)) * w3.x * w3.y;
  return clamp(c, 0.0, 1.0);
}

void main() {
  vec2 local = (FlutterFragCoord().xy - uDst.xy) / uDst.zw;
  vec2 uv = uSrc.xy + local * uSrc.zw;
  vec3 c = uBicubic > 0.5 ? catmullRom(uv) : at(uv);

  if (uSharpen > 0.0) {
    vec3 n = at(uv - vec2(0.0, uTexel.y));
    vec3 s = at(uv + vec2(0.0, uTexel.y));
    vec3 w = at(uv - vec2(uTexel.x, 0.0));
    vec3 e = at(uv + vec2(uTexel.x, 0.0));
    float g = c.g, lo = min(g, min(n.g, min(s.g, min(w.g, e.g)))), hi = max(g, max(n.g, max(s.g, max(w.g, e.g))));
    float amp = sqrt(clamp(min(lo, 1.0 - hi) / max(hi, 0.001), 0.0, 1.0));
    float peak = -amp * mix(0.125, 0.2, uSharpen);
    c = clamp((c + (n + s + w + e) * peak) / (1.0 + 4.0 * peak), 0.0, 1.0);
  }

  float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
  c = mix(vec3(luma), c, uSaturation);
  c = clamp((c - 0.5) * uContrast + 0.5, 0.0, 1.0);
  fragColor = vec4(c, 1.0);
}
