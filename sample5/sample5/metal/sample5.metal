//
//  sample.metal
//  blur-shader
//
//  Created by chance.k on 2021/02/03.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;


typedef struct {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
} ImageVertex;

typedef struct {
    float4 position [[position]];
    float2 texCoord;
} ImageOut;


vertex ImageOut imageVertexFunction( ImageVertex in [[stage_in]]) {
    ImageOut out;
    
    
    float4 position = float4(in.position, 1.0);
    out.position = position;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 imageFragmentFunction(ImageOut in [[stage_in]], texture2d<float> texture1 [[texture(0)]]) {
    
    constexpr sampler colorSampler;
    float4 color = texture1.sample(colorSampler, in.texCoord);
    return color;
}


fragment float4 swapFragmentFunction(ImageOut in [[stage_in]],
                                     texture2d<float> texture1 [[texture(0)]],
                                     texture2d<float> texture2 [[texture(1)]],
                                     texture2d<float> texture3 [[texture(2)]]) {
    
    constexpr sampler colorSampler;
    float4 bgColor = texture1.sample(colorSampler, in.texCoord);
    float4 color = texture2.sample(colorSampler, in.texCoord);
    float4 masking = texture3.sample(colorSampler, in.texCoord);
    
    color = float4((bgColor.rgb * masking.r ) + (color.rgb * (1 - masking.r)), 1.0);
    return color;
}
