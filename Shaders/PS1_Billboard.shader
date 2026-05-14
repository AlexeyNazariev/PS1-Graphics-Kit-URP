Shader "Custom/PS1_Billboard_Unlit"
{
    Properties
    {
        [MainTexture] _BaseMap ("Texture", 2D) = "white" {}
        [MainColor] _BaseColor ("Color", Color) = (1, 1, 1, 1)
        _Cutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        _JitterResolution ("Jitter Resolution", Float) = 240
        _ShadowStrength ("Shadow Strength", Range(0.0, 1.0)) = 0.8
        _ShadowSmoothness ("Shadow Smoothness", Range(0.0, 1.0)) = 0.3
    }
    SubShader
    {
        Tags { 
            "RenderType"="TransparentCutout" 
            "Queue"="AlphaTest" 
            "RenderPipeline"="UniversalPipeline" 
        }

        Cull Back 

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS 
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float2 uv : TEXCOORD0;
                float fogCoord : TEXCOORD2;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                float _Cutoff;
                float _JitterResolution;
                float _ShadowStrength;
                float _ShadowSmoothness;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            float4 ApplyJitter(float4 positionCS, float jitterRes)
            {
                float4 pos = positionCS;
                float2 ndc = pos.xy / pos.w;
                ndc = round(ndc * jitterRes) / jitterRes;
                pos.xy = ndc * pos.w;
                return pos;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                
                output.positionCS = ApplyJitter(output.positionCS, _JitterResolution);
                
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.fogCoord = ComputeFogFactor(output.positionCS.z);
                
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                clip(texColor.a - _Cutoff);
                
                half3 finalColor = texColor.rgb * _BaseColor.rgb;
                
                // --- Shadow Logic ---
                float3 pivotWS = GetObjectToWorldMatrix()._m03_m13_m23;
                
                // Многоточечное сэмплирование для плавного перехода
                float4 shadowCoord = TransformWorldToShadowCoord(pivotWS);
                half shadowAtten = GetMainLight(shadowCoord).shadowAttenuation;
                
                // Добавляем 4 дополнительные пробы вокруг пивота для мягкости
                float s = _ShadowSmoothness;
                shadowAtten += GetMainLight(TransformWorldToShadowCoord(pivotWS + float3(s, 0, s))).shadowAttenuation;
                shadowAtten += GetMainLight(TransformWorldToShadowCoord(pivotWS + float3(-s, 0, -s))).shadowAttenuation;
                shadowAtten += GetMainLight(TransformWorldToShadowCoord(pivotWS + float3(s, 0, -s))).shadowAttenuation;
                shadowAtten += GetMainLight(TransformWorldToShadowCoord(pivotWS + float3(-s, 0, s))).shadowAttenuation;
                shadowAtten /= 5.0;

                // Применяем интенсивность тени (чтобы в тени не было слишком черно)
                shadowAtten = lerp(1.0, shadowAtten, _ShadowStrength);

                // 1. Эмбиент
                half3 lighting = SampleSH(float3(0,1,0));

                // 2. Главный свет (Directional)
                Light mainLight = GetMainLight(shadowCoord); // Используем центр для цвета
                lighting += mainLight.color * shadowAtten;

                // 3. Дополнительные источники (Point, Spot)
                uint pixelLightCount = GetAdditionalLightsCount();
                
                #if USE_FORWARD_PLUS
                LIGHT_LOOP_BEGIN(pixelLightCount)
                    Light addLight = GetAdditionalLight(lightIndex, input.positionWS);
                    lighting += addLight.color * (addLight.distanceAttenuation * addLight.shadowAttenuation);
                LIGHT_LOOP_END
                #else
                for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light addLight = GetAdditionalLight(lightIndex, input.positionWS);
                    lighting += addLight.color * (addLight.distanceAttenuation * addLight.shadowAttenuation);
                }
                #endif

                finalColor *= lighting;
                
                finalColor.rgb = MixFog(finalColor.rgb, input.fogCoord);
                
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        // --- ПРОХОД ДЛЯ ГЛУБИНЫ ---
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            float _JitterResolution;
            float4 _BaseMap_ST;
            float _Cutoff;
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            float4 ApplyJitter(float4 positionCS, float jitterRes)
            {
                float4 pos = positionCS;
                float2 ndc = pos.xy / pos.w;
                ndc = round(ndc * jitterRes) / jitterRes;
                pos.xy = ndc * pos.w;
                return pos;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.positionCS = ApplyJitter(output.positionCS, _JitterResolution);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                clip(texColor.a - _Cutoff);
                return 0;
            }
            ENDHLSL
        }
    }
}

