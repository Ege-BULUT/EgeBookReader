#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;

// Analytic cylinder page curl; see memory/research/page-turn.md section 2.
// The paper is flat where s <= 0 (s = signed distance from the fold axis along uN) and rolls over a
// cylinder of radius uR beyond it. Layers are painted bottom to top so every edge can be antialiased.
uniform vec2 uSize;
uniform float uHinge;
uniform float uPageW;
uniform vec2 uN;
uniform float uT;
uniform float uR;
uniform float uShowThrough;
uniform vec3 uPaper;
uniform float uMirror;
uniform sampler2D uFront;
uniform sampler2D uBack;
uniform sampler2D uUnder;
uniform sampler2D uLeft;

out vec4 fragColor;

const float PI = 3.14159265;

vec2 paperUV(vec2 p) { return vec2((p.x - uHinge) / uPageW, p.y / uSize.y); }

// Right-to-left reading draws the whole turn mirrored, so each page is sampled mirrored to read the right way round.
vec2 mir(vec2 uv) { return vec2(uMirror > 0.5 ? 1.0 - uv.x : uv.x, uv.y); }

// Signed distance from p to the paper's edges: positive inside.
float inside(vec2 p) {
  return min(min(p.x - uHinge, uHinge + uPageW - p.x), min(p.y, uSize.y - p.y));
}

float coverage(vec2 p) { return clamp(inside(p) + 0.5, 0.0, 1.0); }

vec3 frontAt(vec2 p) { return texture(uFront, mir(paperUV(p))).rgb; }

vec3 backAt(vec2 p) {
  vec2 uv = paperUV(p);
  if (uShowThrough > 0.5) return mix(texture(uBack, mir(uv)).rgb, uPaper, 0.86);
  uv.x = 1.0 - uv.x;
  return texture(uBack, mir(uv)).rgb;
}

void main() {
  vec2 q = FlutterFragCoord().xy;
  float s = dot(q, uN) - uT;
  bool dark = dot(uPaper, vec3(0.299, 0.587, 0.114)) < 0.25;

  vec3 color = q.x < uHinge ? texture(uLeft, mir(vec2(q.x / uHinge, q.y / uSize.y))).rgb
                            : texture(uUnder, mir(paperUV(q))).rgb;

  if (s <= 0.0 && inside(q) >= 0.0) color = frontAt(q);

  // Shadow the flap and the roll cast on whatever lies below them.
  vec2 flap = q + uN * (PI * uR - 2.0 * s);
  float outside = max(0.0, -inside(flap));
  float reach = max(uR * 1.3, 1.0);
  float shadow = s <= uR ? 0.26 * (1.0 - smoothstep(0.0, reach, outside)) : 0.0;
  if (s > uR) shadow = 0.34 * exp(-(s - uR) / reach);
  color *= 1.0 - shadow;

  if (s > 0.0 && s < uR) {
    float a = asin(s / uR);
    vec2 p = q + uN * (uR * a - s);
    float c = cos(a);
    vec3 lit = frontAt(p) * mix(0.70, 1.0, c) + vec3(dark ? 0.10 : 0.05) * pow(sin(a * 2.0), 4.0);
    color = mix(color, lit, coverage(p));
  }

  if (s > -1.0 && s < uR) {
    float a = PI - asin(clamp(s, 0.0, uR) / uR);
    vec2 p = q + uN * (uR * a - s);
    float c = -cos(a);
    vec3 lit = backAt(p) * mix(0.74, 1.0, c) + vec3(dark ? 0.12 : 0.04) * pow(sin(a), 6.0);
    color = mix(color, lit, coverage(p));
  }

  if (s <= 0.0) {
    color = mix(color, backAt(flap) * 0.97 + vec3(dark ? 0.03 : 0.0), coverage(flap));
  }

  fragColor = vec4(color, 1.0);
}
