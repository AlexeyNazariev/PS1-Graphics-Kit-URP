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
            // Используем round для более стабильного "прилипания" к сетке
            ndc = round(ndc * jitterRes) / jitterRes;
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
            
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile_fragment _ _DBUFFER_MRT1 _DBUFFER_MRT2 _DBUFFER_MRT3
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DBuffer.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD3;
                float2 uv : TEXCOORD0;
                float4 screenPos : TEXCOORD4;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.positionCS = TransformWorldToHClip(output.positionWS);

                // МАГИЯ PS1: Дрожание в Clip Space
                output.positionCS = ApplyJitter(output.positionCS, _JitterResolution);
                
                // Вычисляем координаты для Screen Space теней
                output.screenPos = ComputeScreenPos(output.positionCS);

                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                input.normalWS = normalize(input.normalWS);
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                clip(texColor.a - _Cutoff);

                // Поддержка Screen Space теней (убирает баг с кругом вокруг нулевых координат)
                #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
                    float4 shadowCoord = input.screenPos;
                #else
                    // Убран ручной отступ (bias), так как он ломал Cascade 0 (ближние тени), создавая светлый круг вокруг камеры.
                    // Смещение теней должно настраиваться только в компоненте Light.
                    float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                #endif
                
                                // 1. Эмбиент
                half3 lighting = SampleSH(input.normalWS);
                
                // 2. Главный свет
                Light mainLight = GetMainLight(shadowCoord);
                half NdotL = saturate(dot(input.normalWS, mainLight.direction));
                lighting += mainLight.color * (mainLight.shadowAttenuation * NdotL);

                // 3. Дополнительные источники
                #if defined(_ADDITIONAL_LIGHTS) || defined(_ADDITIONAL_LIGHTS_VERTEX)
                uint pixelLightCount = GetAdditionalLightsCount();
                #if USE_FORWARD_PLUS
                LIGHT_LOOP_BEGIN(pixelLightCount)
                    Light addLight = GetAdditionalLight(lightIndex, input.positionWS);
                    half NdotLAdd = saturate(dot(input.normalWS, addLight.direction));
                    lighting += addLight.color * (addLight.distanceAttenuation * addLight.shadowAttenuation * NdotLAdd);
                LIGHT_LOOP_END
                #else
                for (uint i = 0u; i < pixelLightCount; ++i)
                {
                    Light addLight = GetAdditionalLight(i, input.positionWS);
                    half NdotLAdd = saturate(dot(input.normalWS, addLight.direction));
                    lighting += addLight.color * (addLight.distanceAttenuation * addLight.shadowAttenuation * NdotLAdd);
                }
                #endif
                #endif

                half3 albedo = texColor.rgb * _BaseColor.rgb;

                // --- ПОДДЕРЖКА ДЕКАЛЕЙ (UNITY 6 DBUFFER) ---
                #if defined(_DBUFFER)
                    ApplyDecalToBaseColor(input.positionCS, albedo);
                #endif

                half3 finalColor = albedo * lighting;

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
                
                // Ручной расчет позиции для теней с учетом Bias
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));

                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                output.positionCS = positionCS;
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
                
                // Возвращаем Jitter в глубину, чтобы избежать Z-fighting (разрывов меша)
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
 
                // Возвращаем Jitter в нормали
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
