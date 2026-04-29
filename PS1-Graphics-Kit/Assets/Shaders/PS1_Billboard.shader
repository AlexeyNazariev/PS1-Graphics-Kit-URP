Shader "Custom/PS1_Billboard_Unlit"
{
    Properties
    {
        _BaseMap ("Texture", 2D) = "white" {}
        _BaseColor ("Color", Color) = (1, 1, 1, 1)
        _Cutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        _JitterResolution ("Jitter Resolution", Float) = 240
    }
    SubShader
    {
        Tags { 
            "RenderType"="TransparentCutout" 
            "Queue"="AlphaTest" 
            "RenderPipeline"="UniversalPipeline" 
        }

        // РИСУЕМ ТОЛЬКО ПЕРЕДНЮЮ СТОРОНУ
        Cull Back 

        Pass
        {
            Name "Unlit"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // Включаем поддержку тумана
            #pragma multi_compile_fog 
            
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
                float fogCoord : TEXCOORD1;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                float _Cutoff;
                float _JitterResolution;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            // Наша любимая магия дрожания
            float4 ApplyJitter(float4 positionCS, float jitterRes)
            {
                float4 pos = positionCS;
                float2 ndc = pos.xy / pos.w;
                ndc = floor(ndc * jitterRes) / jitterRes;
                pos.xy = ndc * pos.w;
                return pos;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                
                // Применяем Jitter
                output.positionCS = ApplyJitter(output.positionCS, _JitterResolution);
                
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                
                // Вычисляем туман
                output.fogCoord = ComputeFogFactor(output.positionCS.z);
                
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                
                // Отрезаем прозрачные пиксели
                clip(texColor.a - _Cutoff);
                
                half3 finalColor = texColor.rgb * _BaseColor.rgb;
                
                // Применяем туман, чтобы кусты красиво исчезали вдалеке
                finalColor.rgb = MixFog(finalColor.rgb, input.fogCoord);
                
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}
