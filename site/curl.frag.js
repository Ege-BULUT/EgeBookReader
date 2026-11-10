// The same analytic cylinder curl as the app's shaders/page_curl.frag, in GLSL ES 3.0.
const CURL_FRAG = `#version 300 es
precision highp float;
uniform vec2 uSize; uniform float uHinge, uPageW, uT, uR, uShowThrough; uniform vec2 uN; uniform vec3 uPaper;
uniform sampler2D uFront, uBack, uUnder, uLeft;
in vec2 v; out vec4 fragColor;
const float PI = 3.14159265;
vec2 paperUV(vec2 p){ return vec2((p.x-uHinge)/uPageW, p.y/uSize.y); }
float inside(vec2 p){ return min(min(p.x-uHinge, uHinge+uPageW-p.x), min(p.y, uSize.y-p.y)); }
float coverage(vec2 p){ return clamp(inside(p)+.5,0.,1.); }
vec3 frontAt(vec2 p){ return texture(uFront,paperUV(p)).rgb; }
vec3 backAt(vec2 p){ vec2 uv=paperUV(p); if(uShowThrough>.5) return mix(texture(uBack,uv).rgb,uPaper,.86); uv.x=1.-uv.x; return texture(uBack,uv).rgb; }
void main(){
  vec2 q=v*uSize;
  float s=dot(q,uN)-uT;
  vec3 color = q.x<uHinge ? texture(uLeft,vec2(q.x/uHinge,q.y/uSize.y)).rgb : texture(uUnder,paperUV(q)).rgb;
  if(s<=0.&&inside(q)>=0.) color=frontAt(q);
  vec2 flap=q+uN*(PI*uR-2.*s);
  float outside=max(0.,-inside(flap));
  float reach=max(uR*1.3,1.);
  float shadow= s<=uR ? .26*(1.-smoothstep(0.,reach,outside)) : .34*exp(-(s-uR)/reach);
  color*=1.-shadow;
  if(s>0.&&s<uR){ float a=asin(s/uR); vec2 p=q+uN*(uR*a-s); vec3 lit=frontAt(p)*mix(.7,1.,cos(a))+vec3(.05)*pow(sin(a*2.),4.); color=mix(color,lit,coverage(p)); }
  if(s>-1.&&s<uR){ float a=PI-asin(clamp(s,0.,uR)/uR); vec2 p=q+uN*(uR*a-s); vec3 lit=backAt(p)*mix(.74,1.,-cos(a))+vec3(.04)*pow(sin(a),6.); color=mix(color,lit,coverage(p)); }
  if(s<=0.) color=mix(color,backAt(flap)*.97,coverage(flap));
  fragColor=vec4(color,1.);
}`;
