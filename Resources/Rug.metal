#include <metal_stdlib>
using namespace metal;
struct Vertex { float4 position; float4 normal; float2 uv; float2 padding; };
struct Uniforms { float4 viewport; }; // width, height, camera distance, shadow pass
struct Out { float4 position [[position]]; float3 normal; float2 uv; float height; };
vertex Out rugVertex(uint id [[vertex_id]],const device Vertex *vertices [[buffer(0)]],constant Uniforms &u [[buffer(1)]]) {
    Vertex v=vertices[id];float3 p=v.position.xyz;
    bool shadow=u.viewport.w>.5;
    if(shadow){p.xy+=float2(.28*p.z+2,.40*p.z+5);p.z=0;}
    float w=max((u.viewport.z-p.z)/u.viewport.z,.4);
    float2 center=u.viewport.xy*.5;
    float2 xy=(p.xy-center)/center;
    xy.y=-xy.y;
    Out out;out.position=float4(xy,(shadow?.99:clamp(.5-p.z/4000.,.01,.95))*w,w);
    out.normal=v.normal.xyz;out.uv=v.uv;out.height=v.position.z;return out;
}
fragment float4 rugFragment(Out in [[stage_in]],bool front [[front_facing]],texture2d<float> texture [[texture(0)]],constant Uniforms &u [[buffer(1)]]) {
    constexpr sampler sample(filter::linear,address::clamp_to_edge);
    float edge=min(min(in.uv.x,1-in.uv.x),min(in.uv.y,1-in.uv.y));
    if(u.viewport.w>.5){float alpha=.16*smoothstep(0.,.009,edge);return float4(float3(.025,.018,.012)*alpha,alpha);}
    float3 color=texture.sample(sample,in.uv).rgb;
    float3 normal=normalize(in.normal);if(!front)normal=-normal;
    float luma=dot(color,float3(.299,.587,.114));
    if(!front){color=mix(color,float3(luma),.46)*.72+float3(.06,.045,.025);float2 knot=fract(in.uv*float2(330,220));float weave=smoothstep(0.,.17,min(min(knot.x,1-knot.x),min(knot.y,1-knot.y)));color*=mix(.87,1.,weave);}
    float3 light=normalize(float3(-.3,-.45,1));
    float shade=(.32+.9*max(dot(normal,light),0.))/(.32+.9*light.z);
    color*=min(shade,1.25)*mix(.64,1.,smoothstep(.0003,.003,edge));
    return float4(min(color,float3(1)),1); // both sides remain fully opaque
}
