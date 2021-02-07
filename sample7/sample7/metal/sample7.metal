//
//  sample.metal
//  blur-shader
//
//  Created by chance.k on 2021/02/03.
//

#include <metal_stdlib>
#include <simd/simd.h>
#import "SharedType.h"

using namespace metal;


typedef struct {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
} ImageVertex;

typedef struct {
    float4 position [[position]];
    float2 texCoord;
} ImageOut;



kernel void gaussianBlurHFunction(
                                 texture2d<float, access::read> input [[texture(0)]],
                                 texture2d<float, access::write> output [[texture(1)]],
                                 constant SharedData &sharedData [[buffer(0)]],
                                 uint2 gid[[thread_position_in_grid]]) {
    
    float3 sum = float3(0.0, 0.0, 0.0);
    for (int i=0;i<sharedData.tapCount;i++) {
        int index = i - (sharedData.tapCount - 1) / 2;
        uint2 id = uint2(gid.x + index, gid.y);
        sum += input.read(id).rgb * sharedData.gaussian[i];
    }
    
    float4 color = float4(sum, 1.0);
    output.write( color, gid);

}

kernel void gaussianBlurVFunction(
                                 texture2d<float, access::read> input [[texture(0)]],
                                 texture2d<float, access::write> output [[texture(1)]],
                                 constant SharedData &sharedData [[buffer(0)]],
                                 uint2 gid[[thread_position_in_grid]]) {
    
    float3 sum = float3(0.0, 0.0, 0.0);
    for (int i=0;i<sharedData.tapCount;i++) {
        int index = i - (sharedData.tapCount - 1) / 2;
        uint2 id = uint2(gid.x, gid.y + index);
        sum += input.read(id).rgb * sharedData.gaussian[i];
    }
    
    float4 color = float4(sum, 1.0);
    output.write( color, gid);

}

vertex ImageOut imageVertexFunction( ImageVertex in [[stage_in]]) {
    ImageOut out;
    
    
    float4 position = float4(in.position, 1.0);
    out.position = position;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 imageResizeFragmentFunction(ImageOut in [[stage_in]],
                                       texture2d<float> texture1 [[texture(0)]] ) {
    constexpr sampler colorSampler;
    float4 color = texture1.sample(colorSampler, in.texCoord);
    return color;
}


fragment float4 swapFragmentFunction(ImageOut in [[stage_in]], texture2d<float> texture1 [[texture(0)]]) {
    
    constexpr sampler colorSampler;
    float4 color = texture1.sample(colorSampler, in.texCoord);
    return color;
}
