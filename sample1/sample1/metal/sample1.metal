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

fragment float4 imageFragmentFunction(ImageOut in [[stage_in]] ) {
    return float4( 1.0, 0.0, 0.0, 1.0);
}

