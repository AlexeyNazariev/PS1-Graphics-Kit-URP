Shader "Custom/PS1_Style_Lit_Alpha_Fixed"
{
    Properties
    {
        _BaseMap ("Texture", 2D) = "white" {}
        _BaseColor ("Color", Color) = (1, 1, 1, 1)
        _JitterResolution ("Jitter Resolution", Float) = 240
        _Cutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
    }
    SubShader
    {
        Tags { 
            "RenderType"="TransparentCutout" 
            "Queue"="AlphaTest" 
            "RenderPipeline"="UniversalPipeline" 
        }
        LOD 100

        // ==========================================
        // ОБЩИЙ КОД (ВЫНЕСЕН ДЛЯ УДОБСТВА)
        // ==========================================
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        // Функция Jitter: вычисляет дрожание в Clip Space
        float4 ApplyJitter(float4 positionCS, float jitterRes)
        {
            float4 pos = positionCS;
            float2 ndc = pos.xy / pos.w;
            ndc = floor(ndc * jitterRes) / jitterRes;
            pos.xy = ndc * pos.w;
            return pos;
        }

        // Общий буфер материалов
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            float _JitterResolution;
            float _Cutoff;
        CBUFFER_END

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);
        ENDHLSL

        // ==========================================
        // ПРОХОД 1: Основной (Цвет + Получение теней)
        // ==========================================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _SHADOWS_SOFT
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
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionCS = TransformWorldToHClip(output.positionWS);

                // МАГИЯ: Используем общую функцию дрожания
                output.positionCS = ApplyJitter(output.positionCS, _JitterResolution);

                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                clip(texColor.a - _Cutoff);

                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half shadowAttenuation = mainLight.shadowAttenuation;

                half3 finalColor = texColor.rgb * _BaseColor.rgb * lerp(0.4, 1.0, shadowAttenuation);
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        // ==========================================
        // ПРОХОД 2: ShadowCaster (Отбрасывание теней)
        // ==========================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            float3 _LightDirection;

            Varyings vert(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));

                // И здесь применяем ту же общую функцию дрожания!
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

        // ==========================================
        // ПРОХОД 3: DepthOnly (Для карты глубины)
        // ==========================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

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

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);

                // И здесь применяем общую функцию дрожания!
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

        // ==========================================
        // ПРОХОД 4: DepthNormals (Для карты нормалей)
        // ==========================================
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD1; // Нам нужны нормали в мире для этой карты
                float2 uv : TEXCOORD0;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);

                // И КРИТИЧЕСКИ ВАЖНО: Применяем дрожание к карте нормалей!
                output.positionCS = ApplyJitter(output.positionCS, _JitterResolution);

                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                clip(texColor.a - _Cutoff);
                
                // Возвращаем нормаль, которая теперь синхронизирована с дрожащей геометрией
                return float4(NormalizeNormalPerPixel(input.normalWS), 0.0);
            }
            ENDHLSL
        }
    }
}
