//
//  FlatShaders.metal
//  RubiksCubeShared
//
//  Created by Administrator on 24/05/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

typedef struct {
    float4 position [[position]];
    float3 worldPositon;
    float3 worldNormal;
    float4 color;
} FlatInOut;

typedef struct {
    float3 position;
    float3 color;
} Light;

constant float lightDistance = 10;
constant float3 lightColor(1, 1, 1);

constant Light lights[] = {
    {
        .position = float3(lightDistance, 0, 0),
        .color = lightColor
    },
    {
        .position = float3(-lightDistance, 0, 0),
        .color = lightColor
    },
    {
        .position = float3(0, lightDistance, 0),
        .color = lightColor
    },
    {
        .position = float3(0, -lightDistance, 0),
        .color = lightColor
    },
    {
        .position = float3(0, 0, lightDistance),
        .color = lightColor
    },
    {
        .position = float3(0, 0, -lightDistance),
        .color = lightColor
    }
};

vertex FlatInOut vertexFlatShader(uint vertexID [[vertex_id]],
                                  constant FlatUniforms &uniforms [[buffer(0)]],
                                  constant FlatVertex *vertices [[buffer(1)]],
                                  constant float4 *colorMap[[buffer(2)]],
                                  constant int *colorMapIndices[[buffer(3)]])
{
    constant FlatVertex &flatVertex = vertices[vertexID];
    
    float4x4 mvp = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix;
    float4 position = float4(flatVertex.position, 1);
    float4 normal = float4(flatVertex.normal, 0);

    FlatInOut out {
        out.position = mvp * position,
        out.worldPositon = (uniforms.modelMatrix * position).xyz,
        out.worldNormal = (uniforms.modelMatrix * normal).xyz,
        out.color = colorMap[colorMapIndices[vertexID]]
    };
    
    return out;
}

fragment float4 fragmentFlatShader(FlatInOut in [[stage_in]],
                                   constant FlatUniforms &uniforms [[buffer(0)]])
{
    float3 baseColor = in.color.rgb;
    float3 diffuseColor = 0;
    float3 specularColor = 0;
    float materialShininess = 16;
    float3 materialSpecularColor = float3(0.25);
    float3 normalDirection = normalize(in.worldNormal);
    for (constant Light &light : lights) {
        float3 lightDirection = normalize(-light.position);
        float diffuseIntensity = saturate(-dot(lightDirection, normalDirection));
        diffuseColor += light.color * baseColor * diffuseIntensity;
        if (diffuseIntensity > 0) {
            float3 reflection = reflect(lightDirection, normalDirection);
            float3 cameraDirection = normalize(in.worldPositon - uniforms.worldCameraPosition);
            float specularIntensity = pow(saturate(-dot(reflection, cameraDirection)), materialShininess);
            specularColor += light.color * materialSpecularColor * specularIntensity;
        }
    }
    float3 color = diffuseColor + specularColor;
    return float4(color, 1);
}
